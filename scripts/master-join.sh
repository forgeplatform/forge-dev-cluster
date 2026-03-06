#!/bin/bash
# Join second control-plane node (k8s-m2) to existing cluster
set -euo pipefail

NODE_IP="${1:?missing NODE_IP}"
SHARED_DIR="/vagrant/shared"

echo "[master-join] Waiting for $SHARED_DIR/master-join.sh from k8s-m1..."
for i in $(seq 1 60); do
    if [ -x "$SHARED_DIR/master-join.sh" ]; then
        break
    fi
    sleep 5
done

if [ ! -x "$SHARED_DIR/master-join.sh" ]; then
    echo "[master-join] ERROR: join script never appeared." >&2
    exit 1
fi

if [ -f /etc/kubernetes/kubelet.conf ]; then
    echo "[master-join] Already joined, skipping."
else
    bash "$SHARED_DIR/master-join.sh" "$NODE_IP"
fi

mkdir -p /home/vagrant/.kube /root/.kube
cp -f /etc/kubernetes/admin.conf /home/vagrant/.kube/config 2>/dev/null || true
cp -f /etc/kubernetes/admin.conf /root/.kube/config 2>/dev/null || true
chown -R vagrant:vagrant /home/vagrant/.kube 2>/dev/null || true

echo "[master-join] Done."
