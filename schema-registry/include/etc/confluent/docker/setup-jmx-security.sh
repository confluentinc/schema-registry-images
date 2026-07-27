#!/bin/bash
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
# Generates a JMX password file and a read-only access file for the remote
# JMX RMI port. Only called when no password file exists yet, so operator-
# supplied credentials are never overwritten.

set -euo pipefail

CONFIG_DIR="${1:?usage: $0 <config-dir>}"
PASSWORD_FILE="$CONFIG_DIR/jmxremote.password"
ACCESS_FILE="$CONFIG_DIR/jmxremote.access"

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | cut -c1-32
  else
    head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-32
  fi
}

mkdir -p "$CONFIG_DIR"

MONITOR_PASSWORD="${SCHEMA_REGISTRY_JMX_MONITOR_PASSWORD:-$(generate_password)}"

cat > "$PASSWORD_FILE" <<EOF
monitorRole $MONITOR_PASSWORD
EOF

cat > "$ACCESS_FILE" <<EOF
monitorRole readonly
EOF

chmod 600 "$PASSWORD_FILE"
chmod 644 "$ACCESS_FILE"

echo "===> Generated JMX credentials at $PASSWORD_FILE (role: monitorRole, access: readonly)"
