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
# Generates JMX password/access files at the given paths, each only if
# missing, so operator-supplied files are never overwritten. If keystore
# arguments are given too, also generates a self-signed TLS keystore.

set -euo pipefail

USAGE="usage: $0 <password-file> <access-file> [keystore-file] [keystore-password-file] [cert-file]"
PASSWORD_FILE="${1:?$USAGE}"
ACCESS_FILE="${2:?$USAGE}"
KEYSTORE_FILE="${3:-}"
KEYSTORE_PASSWORD_FILE="${4:-}"
CERT_FILE="${5:-}"

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | cut -c1-32
  else
    head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-32
  fi
}

mkdir -p "$(dirname "$PASSWORD_FILE")" "$(dirname "$ACCESS_FILE")"
[ -n "$KEYSTORE_FILE" ] && mkdir -p "$(dirname "$KEYSTORE_FILE")"
umask 077

if [ ! -f "$PASSWORD_FILE" ]; then
  MONITOR_PASSWORD="${SCHEMA_REGISTRY_JMX_MONITOR_PASSWORD:-$(generate_password)}"

  cat > "$PASSWORD_FILE" <<EOF
monitorRole $MONITOR_PASSWORD
EOF

  chmod 600 "$PASSWORD_FILE"
  echo "===> Generated JMX password file at $PASSWORD_FILE (role: monitorRole)"
fi

if [ ! -f "$ACCESS_FILE" ]; then
  cat > "$ACCESS_FILE" <<EOF
monitorRole readonly
EOF

  chmod 644 "$ACCESS_FILE"
  echo "===> Generated JMX access file at $ACCESS_FILE (access: readonly)"
fi

if [ -n "$KEYSTORE_FILE" ] && [ ! -f "$KEYSTORE_FILE" ]; then
  KEYSTORE_PASSWORD="${SCHEMA_REGISTRY_JMX_KEYSTORE_PASSWORD:-$(generate_password)}"
  JMX_TLS_HOSTNAME="${SCHEMA_REGISTRY_JMX_HOSTNAME:-$(hostname -i | cut -d" " -f1)}"

  keytool -genkeypair -alias jmx -keyalg RSA -keysize 2048 -validity 3650 \
    -keystore "$KEYSTORE_FILE" -storepass "$KEYSTORE_PASSWORD" -keypass "$KEYSTORE_PASSWORD" \
    -dname "CN=$JMX_TLS_HOSTNAME" -noprompt >/dev/null

  echo "$KEYSTORE_PASSWORD" > "$KEYSTORE_PASSWORD_FILE"
  chmod 600 "$KEYSTORE_FILE" "$KEYSTORE_PASSWORD_FILE"

  keytool -exportcert -alias jmx -keystore "$KEYSTORE_FILE" -storepass "$KEYSTORE_PASSWORD" \
    -rfc -file "$CERT_FILE" >/dev/null
  chmod 644 "$CERT_FILE"

  echo "===> Generated self-signed JMX TLS keystore at $KEYSTORE_FILE (CN=$JMX_TLS_HOSTNAME); public cert exported to $CERT_FILE for clients to trust"
fi
