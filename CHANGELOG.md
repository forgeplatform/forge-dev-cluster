# Changelog

All notable changes to the Forge dev-cluster will be documented in
this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to CalVer (`YYYY.MM.PATCH`).

## [Unreleased]

## [2026.04.0] - 2026-04-28

### Changed
- `post-cluster-setup.sh` and `README.md` now reference the
  `forge-helm` chart at `../forge-helm` (was `../forge-deploy/helm`
  before the chart was extracted into its own repo)

## [2026.03.0] - 2026-03-15

### Added
- 4-VM Vagrant + VirtualBox cluster: 2 control-plane (`k8s-m1`,
  `k8s-m2`) + 2 worker (`k8s-w1`, `k8s-w2`), all on host-only
  network `192.168.56.30-33`
- Provisioning scripts: `common.sh` (containerd + kubeadm prereqs),
  `master-init.sh` (kubeadm init + Flannel), `master-join.sh`,
  `worker-join.sh`
- Flannel `--iface=eth1` patch baked into `master-init.sh` so
  pod-to-pod traffic uses the VirtualBox host-only adapter instead
  of the NAT adapter (without this, cross-node Service VIPs are
  unreachable)
- `post-cluster-setup.sh` installs local-path-provisioner (default
  StorageClass), Traefik IngressController on NodePort 30080/30443,
  the `forge` namespace, plus pre-created `harbor-pull` and
  `forge-tls` secrets
- `shared/` directory mounted into every VM for kubeadm join tokens
  and `admin.conf` export
