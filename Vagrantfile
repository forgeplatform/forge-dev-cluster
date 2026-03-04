# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Forge Platform — k8s test environment (multi-VM)
#
# Layout:
#   k8s-m1  192.168.56.30  control-plane (init, control-plane-endpoint)
#   k8s-m2  192.168.56.31  control-plane (joins via shared join script)
#   k8s-w1  192.168.56.32  worker
#   k8s-w2  192.168.56.33  worker
#
# Total: 8 vCPU, 8 GB RAM (2 vCPU / 2 GB per VM)
# Kubernetes: v1.30 via kubeadm, containerd runtime, Flannel CNI
#
# Usage:
#   vagrant up                # bring up whole cluster (m1 first, then m2/w1/w2)
#   vagrant ssh k8s-m1
#   kubectl get nodes -o wide
#
# Tear down:
#   vagrant destroy -f

NODES = [
  { name: "k8s-m1", ip: "192.168.56.30", role: "master-init", cpus: 2, mem: 2048 },
  { name: "k8s-m2", ip: "192.168.56.31", role: "master-join", cpus: 2, mem: 2048 },
  { name: "k8s-w1", ip: "192.168.56.32", role: "worker",      cpus: 2, mem: 2048 },
  { name: "k8s-w2", ip: "192.168.56.33", role: "worker",      cpus: 2, mem: 2048 },
]

CONTROL_PLANE_ENDPOINT = "192.168.56.30:6443"

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"

  # Make sure /vagrant/shared is writable from m1 so it can drop join scripts
  # for the other VMs to consume. Default rsync sync would be one-way, so we
  # use the synced_folder default (virtualbox shared folder for vbox provider).
  config.vm.synced_folder ".", "/vagrant"

  NODES.each do |node|
    config.vm.define node[:name] do |vm|
      vm.vm.hostname = node[:name]
      vm.vm.network "private_network", ip: node[:ip]

      vm.vm.provider "virtualbox" do |vb|
        vb.name   = node[:name]
        vb.cpus   = node[:cpus]
        vb.memory = node[:mem]
        vb.linked_clone = true
      end

      vm.vm.provider "libvirt" do |lv|
        lv.cpus   = node[:cpus]
        lv.memory = node[:mem]
      end

      # 1) Common provisioning (containerd, kubeadm, kubelet, sysctl, swap off)
      vm.vm.provision "common", type: "shell",
        path: "scripts/common.sh",
        args: [node[:ip], node[:name]]

      # 2) Role-specific provisioning
      case node[:role]
      when "master-init"
        vm.vm.provision "k8s", type: "shell",
          path: "scripts/master-init.sh",
          args: [node[:ip], CONTROL_PLANE_ENDPOINT]
      when "master-join"
        vm.vm.provision "k8s", type: "shell",
          path: "scripts/master-join.sh",
          args: [node[:ip]]
      when "worker"
        vm.vm.provision "k8s", type: "shell",
          path: "scripts/worker-join.sh"
      end
    end
  end
end
