#!/bin/bash
# Join worker node to existing cluster
set -euo pipefail

SHARED_DIR="/vagrant/shared"

echo "[worker-join] Waiting for $SHARED_DIR/worker-join.sh from k8s-m1..."
for i in $(seq 1 60); do
    if [ -x "$SHARED_DIR/worker-join.sh" ]; then
        break
    fi
    sleep 5
done

if [ ! -x "$SHARED_DIR/worker-join.sh" ]; then
    echo "[worker-join] ERROR: join script never appeared." >&2
    exit 1
fi

if [ -f /etc/kubernetes/kubelet.conf ]; then
    echo "[worker-join] Already joined, skipping."
else
    bash "$SHARED_DIR/worker-join.sh"
fi

echo "[worker-join] Done."
