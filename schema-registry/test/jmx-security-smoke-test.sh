#!/usr/bin/env bash
#
# Copyright 2026 Confluent Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Verifies remote JMX is unreachable by default, and requires auth + enforces
# readonly access when enabled via SCHEMA_REGISTRY_JMX_REMOTE_ENABLE. Runs
# real containers and a real JMX/RMI client -- nothing here is mocked.
#
# Usage: jmx-security-smoke-test.sh <schema-registry-image>

set -euo pipefail

IMAGE="${1:?usage: $0 <schema-registry-image>}"

RUN_ID="jmx-smoke-$$"
NET="${RUN_ID}-net"
DEFAULT_CONTAINER="${RUN_ID}-default"
REMOTE_CONTAINER="${RUN_ID}-remote"
CLIENT_IMAGE="${RUN_ID}-jmxterm"
WORKDIR="$(mktemp -d)"

FAILURES=0

log() { echo "===> $*"; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAILURES=$((FAILURES + 1)); }

cleanup() {
  log "Cleaning up"
  docker rm -f "$DEFAULT_CONTAINER" "$REMOTE_CONTAINER" "${KAFKA_CONTAINER:-}" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  docker rmi "$CLIENT_IMAGE" >/dev/null 2>&1 || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

log "Building minimal jmxterm client image"
curl -fsL -o "$WORKDIR/jmxterm.jar" \
  https://github.com/jiaqi/jmxterm/releases/download/v1.0.4/jmxterm-1.0.4-uber.jar
cat > "$WORKDIR/Dockerfile" <<'EOF'
FROM eclipse-temurin:17-jre
COPY jmxterm.jar /jmxterm.jar
EOF
docker build -q -t "$CLIENT_IMAGE" "$WORKDIR" >/dev/null

docker network create "$NET" >/dev/null

KAFKA_CONTAINER="${RUN_ID}-kafka"

log "Starting a single-node Kafka broker for schema-registry to talk to"
docker run -d --name "$KAFKA_CONTAINER" --network "$NET" \
  -e KAFKA_PROCESS_ROLES=broker,controller \
  -e KAFKA_NODE_ID=1 \
  -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
  -e KAFKA_CONTROLLER_QUORUM_VOTERS="1@${KAFKA_CONTAINER}:49152" \
  -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
  -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT \
  -e KAFKA_LISTENERS="CONTROLLER://${KAFKA_CONTAINER}:49152,PLAINTEXT://${KAFKA_CONTAINER}:9092" \
  -e KAFKA_INTER_BROKER_LISTENER_NAME=PLAINTEXT \
  -e KAFKA_ADVERTISED_LISTENERS="PLAINTEXT://${KAFKA_CONTAINER}:9092" \
  -e CLUSTER_ID=MkU3OEVBNTcwNTJENDM2Qk \
  confluentinc/cp-kafka:latest >/dev/null

tries=60
until docker exec "$KAFKA_CONTAINER" kafka-topics --bootstrap-server "${KAFKA_CONTAINER}:9092" --list >/dev/null 2>&1; do
  tries=$((tries - 1))
  if [ "$tries" -le 0 ]; then
    log "Kafka broker did not become ready in time; logs:"
    docker logs "$KAFKA_CONTAINER" 2>&1 | tail -30
    exit 1
  fi
  sleep 2
done
log "Kafka broker is ready"

wait_for_ready() {
  local container="$1"
  if docker exec "$container" ub sr-ready localhost 8081 120 >/dev/null 2>&1; then
    return 0
  fi
  log "Container $container did not become ready in time; logs:"
  docker logs "$container" 2>&1 | tail -30
  return 1
}

common_env=(
  -e SCHEMA_REGISTRY_HOST_NAME=smoke-test
  -e SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS="PLAINTEXT://${KAFKA_CONTAINER}:9092"
)

# --- Scenario 1: default (SCHEMA_REGISTRY_JMX_PORT set, remote not enabled) ---
log "Starting container with SCHEMA_REGISTRY_JMX_PORT set, remote JMX NOT enabled"
docker run -d --name "$DEFAULT_CONTAINER" --network "$NET" \
  "${common_env[@]}" \
  -e SCHEMA_REGISTRY_JMX_PORT=9999 \
  "$IMAGE" >/dev/null
wait_for_ready "$DEFAULT_CONTAINER"

output=$(docker run --rm --network "$NET" "$CLIENT_IMAGE" \
  bash -c "echo beans | timeout 10 java -jar /jmxterm.jar -l ${DEFAULT_CONTAINER}:9999 -n -v verbose" 2>&1 || true)
if echo "$output" | grep -q "Connection refused\|ConnectException"; then
  pass "remote JMX is unreachable by default (connection refused)"
else
  fail "expected remote JMX to be unreachable by default; got: $output"
fi

# --- Scenario 2: remote explicitly enabled ---
log "Starting container with SCHEMA_REGISTRY_JMX_REMOTE_ENABLE=true"
docker run -d --name "$REMOTE_CONTAINER" --network "$NET" \
  "${common_env[@]}" \
  -e SCHEMA_REGISTRY_JMX_PORT=9999 \
  -e SCHEMA_REGISTRY_JMX_REMOTE_ENABLE=true \
  "$IMAGE" >/dev/null
wait_for_ready "$REMOTE_CONTAINER"

PASSWORD=$(docker exec "$REMOTE_CONTAINER" grep '^monitorRole' /etc/schema-registry/secrets/jmxremote.password | awk '{print $2}')
if [ -z "$PASSWORD" ]; then
  fail "no JMX password was generated when remote JMX was enabled"
  PASSWORD="unused"
else
  pass "a JMX password file was generated when remote JMX was enabled"
fi

no_creds=$(docker run --rm --network "$NET" "$CLIENT_IMAGE" \
  bash -c "echo beans | timeout 10 java -jar /jmxterm.jar -l ${REMOTE_CONTAINER}:9999 -n -v verbose" 2>&1 || true)
if echo "$no_creds" | grep -q "Credentials required"; then
  pass "remote JMX requires authentication when enabled"
else
  fail "expected remote JMX to require credentials; got: $no_creds"
fi

wrong_creds=$(docker run --rm --network "$NET" "$CLIENT_IMAGE" \
  bash -c "echo beans | timeout 10 java -jar /jmxterm.jar -l ${REMOTE_CONTAINER}:9999 -u monitorRole -p wrong -n -v verbose" 2>&1 || true)
if echo "$wrong_creds" | grep -q "Invalid username or password"; then
  pass "remote JMX rejects an incorrect password"
else
  fail "expected remote JMX to reject a wrong password; got: $wrong_creds"
fi

read_result=$(docker run --rm --network "$NET" "$CLIENT_IMAGE" \
  bash -c "echo 'get -b java.lang:type=Memory HeapMemoryUsage' | timeout 10 java -jar /jmxterm.jar -l ${REMOTE_CONTAINER}:9999 -u monitorRole -p $PASSWORD -n -v verbose" 2>&1 || true)
if echo "$read_result" | grep -q "HeapMemoryUsage"; then
  pass "remote JMX allows a read with the generated credentials"
else
  fail "expected a successful read with generated credentials; got: $read_result"
fi

write_result=$(docker run --rm --network "$NET" "$CLIENT_IMAGE" \
  bash -c "echo 'set -b java.lang:type=Threading ThreadContentionMonitoringEnabled true' | timeout 10 java -jar /jmxterm.jar -l ${REMOTE_CONTAINER}:9999 -u monitorRole -p $PASSWORD -n -v verbose" 2>&1 || true)
if echo "$write_result" | grep -q "Access denied"; then
  pass "remote JMX enforces readonly access (attribute writes denied)"
else
  fail "expected a write operation to be denied; got: $write_result"
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "All JMX security smoke tests passed."
  exit 0
else
  echo "$FAILURES JMX security smoke test(s) failed."
  exit 1
fi
