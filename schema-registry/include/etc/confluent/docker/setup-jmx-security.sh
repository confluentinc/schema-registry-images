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
# Generates a JMX password/access file at the given paths, each only if
# missing, so operator-supplied credentials are never overwritten.

set -euo pipefail

PASSWORD_FILE="${1:?usage: $0 <password-file> <access-file>}"
ACCESS_FILE="${2:?usage: $0 <password-file> <access-file>}"

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | cut -c1-32
  else
    head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-32
  fi
}

mkdir -p "$(dirname "$PASSWORD_FILE")" "$(dirname "$ACCESS_FILE")"
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
