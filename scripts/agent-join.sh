#!/bin/bash
# Join k3s agent (worker) to an existing cluster.
set -euo pipefail

NODE_IP="${1:?missing NODE_IP}"
INIT_SERVER_IP="${2:?missing INIT_SERVER_IP}"
K3S_TOKEN="${3:?missing K3S_TOKEN}"
K3S_VERSION="${4:?missing K3S_VERSION}"

echo "============================================"
echo " [agent-join] $NODE_IP -> $INIT_SERVER_IP"
echo "============================================"

for i in $(seq 1 60); do
    if curl -sk --max-time 3 "https://${INIT_SERVER_IP}:6443/livez" >/dev/null 2>&1; then
        break
    fi
    sleep 5
done

if [ -f /etc/systemd/system/k3s-agent.service ]; then
    echo "[agent-join] k3s-agent already installed, skipping."
else
    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_VERSION="$K3S_VERSION" \
        K3S_TOKEN="$K3S_TOKEN" \
        K3S_URL="https://${INIT_SERVER_IP}:6443" \
        sh -s - agent \
            --node-ip="$NODE_IP" \
            --flannel-iface=eth1
fi

echo "[agent-join] Done."
