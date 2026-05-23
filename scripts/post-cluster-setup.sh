#!/bin/bash
# Post-cluster bootstrap for the forge namespace.
#
# k3s already ships:
#   * Traefik IngressController (default IngressClass)
#   * local-path StorageClass (default)
#   * klipper LoadBalancer controller (servicelb)
#   * CoreDNS, metrics-server
#
# So this script only creates the forge namespace and its prerequisite
# secrets (Harbor pull credentials + self-signed TLS for forge.local).
# Idempotent — re-run safely.
#
# Usage:
#   vagrant ssh k8s-m1 -c "bash /vagrant/scripts/post-cluster-setup.sh"
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
KUBECTL="kubectl"
HARBOR_REGISTRY="${HARBOR_REGISTRY:-ghcr.io}"
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_PASS="${HARBOR_PASS:-CHANGE_ME}"

echo "[1/4] Waiting for built-in components (Traefik, local-path)..."
$KUBECTL -n kube-system rollout status deploy/traefik --timeout=300s || true
$KUBECTL -n kube-system rollout status deploy/local-path-provisioner --timeout=180s || true

echo "[2/4] Creating forge namespace + Harbor pull-secret..."
$KUBECTL create ns forge --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL -n forge create secret docker-registry harbor-pull \
    --docker-server="$HARBOR_REGISTRY" \
    --docker-username="$HARBOR_USER" \
    --docker-password="$HARBOR_PASS" \
    --dry-run=client -o yaml | $KUBECTL apply -f -

echo "[3/4] Generating self-signed TLS cert for forge.local..."
TLS_DIR=$(mktemp -d)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$TLS_DIR/tls.key" -out "$TLS_DIR/tls.crt" \
    -subj '/CN=forge.local/O=Forge Dev' \
    -addext 'subjectAltName=DNS:forge.local,DNS:*.forge.local,IP:192.168.56.30,IP:192.168.56.31,IP:192.168.56.32,IP:192.168.56.33,IP:192.168.56.34,IP:192.168.56.35,IP:192.168.56.36' 2>/dev/null
$KUBECTL -n forge create secret tls forge-tls \
    --cert="$TLS_DIR/tls.crt" --key="$TLS_DIR/tls.key" \
    --dry-run=client -o yaml | $KUBECTL apply -f -
rm -rf "$TLS_DIR"

echo "[4/4] Cluster ready."
$KUBECTL get nodes -o wide
$KUBECTL -n kube-system get pods

cat <<EOF

==================================================
 Cluster pre-reqs ready.
==================================================

 Storage:           local-path (default)
 Ingress:           Traefik (built into k3s, ClusterIP + LoadBalancer)
                    LoadBalancer IPs allocated by klipper-lb to a node IP
 forge namespace:   created (with harbor-pull + forge-tls secrets)

 Now deploy Forge:

   # On the host, with KUBECONFIG pointed at shared/admin.conf:
   export KUBECONFIG=\$(pwd)/shared/admin.conf
   helm install forge ../forge-helm -n forge

 And operator:

   TOKEN=\$(kubectl -n forge exec deploy/forge-web -- forge-manage create_oauth2_token --user admin | tail -1)
   helm install forge-operator ../forge-operator/helm -n forge-operator --create-namespace \\
     --set forge.token=\$TOKEN \\
     --set forge.url=http://forge-web.forge.svc.cluster.local:8013

 Browser access (after Forge install):

   http://forge.local        (Traefik LoadBalancer on :80)
   https://forge.local       (Traefik LoadBalancer on :443, self-signed)
   /etc/hosts:  192.168.56.33  forge.local   # any worker IP works

EOF
