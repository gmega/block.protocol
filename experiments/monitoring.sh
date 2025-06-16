#!/usr/bin/env bash
#
set -e

TARGETS_DIR="$(dirname "$0")/monitoring/targets"
rm -rf "${TARGETS_DIR:?}/"*
mkdir -p "$TARGETS_DIR"

echoerr() {
    echo "$@" >&2
}

# Starts monitoring node under Prometheus
start_monitoring_node() {
    local port=$1
    local node_file="$TARGETS_DIR/node-$port.json"

    cat > "$node_file" << EOF
[
  {
    "targets": ["localhost:$port"],
    "labels": {
      "job": "codex-metrics",
      "environment": "local",
      "node_port": "$port"
    }
  }
]
EOF
    echoerr "Created target file for port $port: $node_file"
}

# Stops monitoring node under prometheus
stop_monitoring_node() {
    rm -rf "$TARGETS_DIR/node-$port.json"
}
