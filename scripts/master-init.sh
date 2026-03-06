#!/bin/bash
# Initialize first control-plane node (k8s-m1)
# After init, drops join commands into /vagrant/shared/ for the other nodes.
set -euo pipefail

NODE_IP="${1:?missing NODE_IP}"
CONTROL_PLANE_ENDPOINT="${2:?missing CONTROL_PLANE_ENDPOINT}"

POD_CIDR="10.244.0.0/16"
SHARED_DIR="/vagrant/shared"

echo "============================================"
echo " [master-init] $NODE_IP -> $CONTROL_PLANE_ENDPOINT"
echo "============================================"

mkdir -p "$SHARED_DIR"

if [ -f /etc/kubernetes/admin.conf ]; then
    echo "[master-init] Already initialized, skipping kubeadm init."
else
    kubeadm init \
        --apiserver-advertise-address="$NODE_IP" \
        --control-plane-endpoint="$CONTROL_PLANE_ENDPOINT" \
        --pod-network-cidr="$POD_CIDR" \
        --kubernetes-version=v1.30.4 \
        --upload-certs \
        --cri-socket unix:///run/containerd/containerd.sock \
        | tee /tmp/kubeadm-init.log
fi

# kubectl for vagrant + root
mkdir -p /home/vagrant/.kube /root/.kube
cp -f /etc/kubernetes/admin.conf /home/vagrant/.kube/config
cp -f /etc/kubernetes/admin.conf /root/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube

# --- Install Flannel CNI ---
#
# IMPORTANT: VirtualBox VMs here have two NICs — eth0 (NAT, internet) and
# eth1 (host-only, 192.168.56.x for inter-VM traffic). Flannel's default
# backend picks the first interface with a default route, which is eth0.
# But every VM gets the same NAT IP (10.0.2.15), so VXLAN tunnels never
# reach across nodes — symptom: Service VIPs unreachable, DNS times out,
# pods can't talk to the apiserver. Force flannel to bind to eth1 so
# tunnels run over the host-only network where each node has a unique IP.
KUBECTL="kubectl --kubeconfig=/etc/kubernetes/admin.conf"
if ! $KUBECTL get ds -n kube-flannel kube-flannel-ds >/dev/null 2>&1; then
    echo "[master-init] Installing Flannel CNI..."
    $KUBECTL apply -f https://raw.githubusercontent.com/flannel-io/flannel/v0.25.6/Documentation/kube-flannel.yml

    echo "[master-init] Patching flannel to bind VXLAN on eth1..."
    for i in $(seq 1 30); do
        if $KUBECTL -n kube-flannel get ds kube-flannel-ds >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done
    $KUBECTL -n kube-flannel patch ds kube-flannel-ds --type=json \
        -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--iface=eth1"}]'
    $KUBECTL -n kube-flannel rollout status ds/kube-flannel-ds --timeout=180s || true
fi

# --- Generate join commands for other nodes ---
echo "[master-init] Producing join commands in $SHARED_DIR..."

CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)
JOIN_BASE=$(kubeadm token create --print-join-command)

# Worker join
echo "#!/bin/bash" > "$SHARED_DIR/worker-join.sh"
echo "set -euo pipefail" >> "$SHARED_DIR/worker-join.sh"
echo "$JOIN_BASE --cri-socket unix:///run/containerd/containerd.sock" >> "$SHARED_DIR/worker-join.sh"
chmod +x "$SHARED_DIR/worker-join.sh"

# Control-plane join (adds --control-plane and --certificate-key)
echo "#!/bin/bash" > "$SHARED_DIR/master-join.sh"
echo "set -euo pipefail" >> "$SHARED_DIR/master-join.sh"
echo "NODE_IP=\"\${1:?missing NODE_IP}\"" >> "$SHARED_DIR/master-join.sh"
echo "$JOIN_BASE --control-plane --certificate-key $CERT_KEY --apiserver-advertise-address \$NODE_IP --cri-socket unix:///run/containerd/containerd.sock" >> "$SHARED_DIR/master-join.sh"
chmod +x "$SHARED_DIR/master-join.sh"

# Copy admin.conf so we can grab it from host if we want
cp /etc/kubernetes/admin.conf "$SHARED_DIR/admin.conf"
chmod 644 "$SHARED_DIR/admin.conf"

echo "[master-init] Done."
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide || true
