# forge-dev-cluster

A 4-node Kubernetes 1.30 test cluster on Vagrant + VirtualBox. Used as
the development / test environment for the Forge Platform components
(`forge-deploy` k8s manifests, `forge-operator`, future Helm charts).

## Topology

| Node | IP | Role | Resources |
|---|---|---|---|
| `k8s-m1` | 192.168.56.30 | control-plane | 2 vCPU / 2 GB |
| `k8s-m2` | 192.168.56.31 | control-plane | 2 vCPU / 2 GB |
| `k8s-w1` | 192.168.56.32 | worker | 2 vCPU / 2 GB |
| `k8s-w2` | 192.168.56.33 | worker | 2 vCPU / 2 GB |

* **CNI:** Flannel (VXLAN bound to `eth1`/host-only — bound from start
  via patched `master-init.sh`)
* **Runtime:** containerd 2.x
* **Box:** `bento/ubuntu-24.04`

## Prerequisites

* VirtualBox 7.0+ (or libvirt as alt provider)
* Vagrant 2.4+
* ~10 GB RAM free
* Ports 22, 6443, 30080, 30443 free on the 192.168.56.0/24 host-only
  network

## Quickstart

```bash
vagrant up                  # ~5–10 min on cached box

# Install StorageClass + Traefik + forge namespace pre-reqs
vagrant ssh k8s-m1 -c "bash /vagrant/scripts/post-cluster-setup.sh"

# Verify
vagrant ssh k8s-m1 -c "kubectl get nodes,pods -A"
```

`shared/admin.conf` is exported on each `master-init` run — point your
host `KUBECONFIG` at it for direct cluster access:

```bash
export KUBECONFIG=$PWD/shared/admin.conf
kubectl get nodes
```

## After cluster is up

This repo only stands up an empty cluster. Forge core and operator
deploy from their own repos:

```bash
# Forge core
helm install forge ../forge-deploy/helm -n forge

# forge-operator
TOKEN=$(kubectl -n forge exec deploy/forge-web -- \
    forge-manage create_oauth2_token --user admin | tail -1)
helm install forge-operator ../forge-operator/helm \
    -n forge-operator --create-namespace \
    --set forge.token=$TOKEN
```

## Tear down

```bash
vagrant destroy -f
```

Removes the four VMs and their disks. Re-run `vagrant up` to recreate
from scratch — provisioning is idempotent.

## Layout

```
forge-dev-cluster/
├── Vagrantfile               # 4-VM multi-machine config
├── scripts/
│   ├── common.sh             # containerd + kubeadm prereqs (all nodes)
│   ├── master-init.sh        # kubeadm init on k8s-m1, Flannel + eth1 patch
│   ├── master-join.sh        # kubeadm join control-plane (k8s-m2)
│   ├── worker-join.sh        # kubeadm join worker (k8s-w1, k8s-w2)
│   └── post-cluster-setup.sh # local-path-provisioner + Traefik + forge ns
└── shared/                   # synced /vagrant/shared (join tokens, admin.conf)
```

## Known issues

* **Pod-to-pod across nodes initially fails until Flannel is patched
  to use `eth1`** — this is automated in `master-init.sh`. If you ever
  see DNS timeouts or `connect: no route to host` between pods on
  different worker nodes, check `kubectl -n kube-flannel get ds
  kube-flannel-ds -o yaml` and confirm the args contain
  `--iface=eth1`.
* **Rolling restarts of cluster-critical DaemonSets (kube-proxy,
  flannel) can leave VirtualBox host-only networking in a bad state**
  due to apiserver↔kubelet TLS handshake timeouts. Symptom: workers
  flap `NotReady`, taints reapply, NodePorts return Connection
  refused. Fix: `vagrant destroy -f && vagrant up`. This is a
  VirtualBox quirk — does not happen on baremetal or libvirt.
