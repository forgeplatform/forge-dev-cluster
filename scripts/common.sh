#!/bin/bash
# Common provisioning for all k8s nodes (Ubuntu 24.04, kubeadm 1.30)
set -euo pipefail

NODE_IP="${1:?missing NODE_IP}"
NODE_HOSTNAME="${2:?missing NODE_HOSTNAME}"

export DEBIAN_FRONTEND=noninteractive

echo "============================================"
echo " [common] $NODE_HOSTNAME ($NODE_IP)"
echo "============================================"

# /etc/hosts entries so nodes can resolve each other by name
cat > /etc/hosts <<EOF
127.0.0.1 localhost
$NODE_IP $NODE_HOSTNAME

192.168.56.30 k8s-m1
192.168.56.31 k8s-m2
192.168.56.32 k8s-w1
192.168.56.33 k8s-w2
EOF

hostnamectl set-hostname "$NODE_HOSTNAME"

# --- Disable swap (kubeadm requirement) ---
echo "[1/6] Disabling swap..."
swapoff -a
sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab
# bento boxes use systemd swapfile units
systemctl mask swap.target 2>/dev/null || true
rm -f /swap.img 2>/dev/null || true

# --- Kernel modules ---
echo "[2/6] Loading kernel modules..."
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# --- sysctl ---
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

# --- Apt prerequisites ---
echo "[3/6] Installing apt prerequisites..."
apt-get update -qq
apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release socat conntrack ipset

# --- Install containerd ---
echo "[4/6] Installing containerd..."
install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y -qq containerd.io

mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' > /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# --- Install kubeadm/kubelet/kubectl 1.30 ---
echo "[5/6] Installing kubeadm/kubelet/kubectl..."
if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
fi
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
    > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Tell kubelet which IP to advertise (private network, not NAT eth0)
mkdir -p /etc/default
cat > /etc/default/kubelet <<EOF
KUBELET_EXTRA_ARGS=--node-ip=$NODE_IP
EOF

# crictl points to containerd
cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
EOF

systemctl enable kubelet

# --- Pre-pull control-plane images (saves time during init/join) ---
echo "[6/6] Pre-pulling kubeadm images..."
kubeadm config images pull --kubernetes-version=v1.30.4 || true

echo "[common] Done for $NODE_HOSTNAME"
