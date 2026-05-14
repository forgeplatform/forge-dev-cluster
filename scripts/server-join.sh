#!/bin/bash
# Join additional k3s server (k8s-m2 / k8s-m3) into existing etcd quorum.
set -euo pipefail

NODE_IP="${1:?missing NODE_IP}"
INIT_SERVER_IP="${2:?missing INIT_SERVER_IP}"
K3S_TOKEN="${3:?missing K3S_TOKEN}"
K3S_VERSION="${4:?missing K3S_VERSION}"

echo "============================================"
echo " [server-join] $NODE_IP -> $INIT_SERVER_IP"
echo "============================================"

# Wait for the init server's API to be ready before attempting to join.
for i in $(seq 1 60); do
    if curl -sk --max-time 3 "https://${INIT_SERVER_IP}:6443/livez" >/dev/null 2>&1; then
        break
    fi
    sleep 5
done

if [ -f /etc/systemd/system/k3s.service ]; then
    echo "[server-join] k3s already installed, skipping."
else
    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_VERSION="$K3S_VERSION" \
        K3S_TOKEN="$K3S_TOKEN" \
        sh -s - server \
            --server "https://${INIT_SERVER_IP}:6443" \
            --node-ip="$NODE_IP" \
            --advertise-address="$NODE_IP" \
            --flannel-iface=eth1 \
            --tls-san=192.168.56.30 \
            --tls-san=192.168.56.31 \
            --tls-san=192.168.56.32 \
            --write-kubeconfig-mode=0644
fi

mkdir -p /home/vagrant/.kube /root/.kube
cp -f /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config 2>/dev/null || true
cp -f /etc/rancher/k3s/k3s.yaml /root/.kube/config 2>/dev/null || true
chown -R vagrant:vagrant /home/vagrant/.kube 2>/dev/null || true

ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl 2>/dev/null || true

echo "[server-join] Done."
