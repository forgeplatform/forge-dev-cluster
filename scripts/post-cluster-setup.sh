#!/bin/bash
# Post-cluster bootstrap: install local-path StorageClass, Traefik
# IngressController, and the forge-system pre-reqs (namespace + Harbor
# pull-secret + TLS secret). Idempotent.
#
# Run inside k8s-m1 after `vagrant up` completes:
#   vagrant ssh k8s-m1 -c "bash /vagrant/scripts/post-cluster-setup.sh"
#
# After this runs, install Forge core + operator separately:
#
#   # Forge core (forge-helm repo)
#   helm install forge ../forge-helm -n forge
#
#   # forge-operator (forge-operator repo). Requires Forge admin OAuth2 PAT:
#   TOKEN=$(kubectl -n forge exec deploy/forge-web -- forge-manage create_oauth2_token --user admin | tail -1)
#   helm install forge-operator ../forge-operator/helm -n forge-operator --create-namespace \
#     --set forge.token=$TOKEN
set -euo pipefail

KUBECTL="kubectl"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
HARBOR_REGISTRY="${HARBOR_REGISTRY:-registry.cloudforyour.work}"
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_PASS="${HARBOR_PASS:-CHANGE_ME}"

echo "[1/4] Installing local-path-provisioner (default StorageClass)..."
$KUBECTL apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
$KUBECTL annotate sc local-path storageclass.kubernetes.io/is-default-class=true --overwrite
$KUBECTL -n local-path-storage rollout status deploy/local-path-provisioner --timeout=180s

echo "[2/4] Creating forge namespace and Harbor pull-secret..."
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
    -addext 'subjectAltName=DNS:forge.local,DNS:*.forge.local,IP:192.168.56.30,IP:192.168.56.31,IP:192.168.56.32,IP:192.168.56.33' 2>/dev/null
$KUBECTL -n forge create secret tls forge-tls \
    --cert="$TLS_DIR/tls.crt" --key="$TLS_DIR/tls.key" \
    --dry-run=client -o yaml | $KUBECTL apply -f -
rm -rf "$TLS_DIR"

echo "[4/4] Installing Traefik ingress controller..."
if ! command -v helm >/dev/null; then
    echo "  helm not found, installing v3.16.2..."
    sudo bash -c 'curl -fsSL https://get.helm.sh/helm-v3.16.2-linux-amd64.tar.gz | tar -xz -C /tmp && mv /tmp/linux-amd64/helm /usr/local/bin/helm && chmod +x /usr/local/bin/helm'
fi
helm repo add traefik https://traefik.github.io/charts 2>/dev/null || true
helm repo update >/dev/null
$KUBECTL create ns traefik --dry-run=client -o yaml | $KUBECTL apply -f -
helm upgrade --install traefik traefik/traefik -n traefik \
    --set service.type=NodePort \
    --set ports.web.nodePort=30080 \
    --set ports.websecure.nodePort=30443 \
    --set ingressClass.enabled=true \
    --set ingressClass.isDefaultClass=true \
    --set providers.kubernetesIngress.allowExternalNameServices=true
$KUBECTL -n traefik rollout status deploy/traefik --timeout=180s

cat <<EOF

==================================================
 Cluster pre-reqs ready.
==================================================

 Storage:           local-path (default)
 Ingress:           Traefik (NodePort web=30080 websecure=30443)
 forge namespace:   created (with harbor-pull + forge-tls secrets)

 Now deploy Forge:

   # In a host shell with KUBECONFIG=$HOME/repos/forge-platform/forge-dev-cluster/shared/admin.conf
   helm install forge ../forge-helm -n forge

 And operator:

   TOKEN=\$(kubectl -n forge exec deploy/forge-web -- forge-manage create_oauth2_token --user admin | tail -1)
   helm install forge-operator ../forge-operator/helm -n forge-operator --create-namespace \\
     --set forge.token=\$TOKEN \\
     --set forge.url=http://forge-web.forge.svc.cluster.local:8013

 Browser access (after Forge install):

   http://forge.local:30080   (plain HTTP)
   https://forge.local:30443  (self-signed TLS — accept warning)
   /etc/hosts:  192.168.56.32  forge.local

EOF
