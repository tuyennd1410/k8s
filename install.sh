#!/bin/bash

# Step 0: Add hostnames to /etc/hosts
echo "Updating /etc/hosts file"
cat >> /etc/hosts << EOF
# Kubernetes Cluster
x.x.x.x  master    # Replace with your actual hostname and IP address
x.x.x.x worker1   # Replace with your actual hostname and IP address
x.x.x.x  worker2   # Replace with your actual hostname and IP address
EOF


# Set the container runtime endpoint for CRI-O compatibility
export CONTAINER_RUNTIME_ENDPOINT=unix:///var/run/containerd/containerd.sock
PATH=""
# Set path as directory upload setup files on server


# Step 1: Install Kernel Headers
echo "Installing kernel headers"
sudo dnf install kernel-devel-$(uname -r) -y

# Step 2: Add Kernel Modules
echo "Loading kernel modules"
sudo modprobe br_netfilter
sudo modprobe ip_vs
sudo modprobe ip_vs_rr
sudo modprobe ip_vs_wrr
sudo modprobe ip_vs_sh
sudo modprobe overlay

# Ensure the modules load on boot
echo "Creating /etc/modules-load.d/kubernetes.conf"
cat > /etc/modules-load.d/kubernetes.conf << EOF
br_netfilter
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
overlay
EOF

# Step 3: Configure Sysctl
echo "Configuring sysctl"
cat > /etc/sysctl.d/kubernetes.conf << EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

# Apply the sysctl settings
sudo sysctl --system

# Clean up YUM packages and upgrade the system
yum clean packages
yum upgrade -y

# Install essential packages needed for Kubernetes and containerd
yum install -y pcre-devel yum-utils device-mapper-persistent-data lvm2 chrony net-tools \
               nc pcre-devel langpacks-en glibc-all-langpacks openssh openssh-clients \
               openssl-devel compat-openssl10
# Step 4: Disable Swap
echo "Disabling swap"
sudo swapoff -a
sudo sed -e '/swap/s/^/#/g' -i /etc/fstab

# Step 5: Install Containerd
echo "Installing containerd"
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf makecache
sudo dnf -y install containerd.io

# Set the correct timezone for the system
timedatectl set-timezone Asia/Ho_Chi_Minh

# Configure containerd
echo "Configuring containerd"
sudo sh -c "containerd config default > /etc/containerd/config.toml"
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Enable and start containerd
sudo systemctl enable --now containerd.service

# Check containerd status
sudo systemctl status containerd.service

# Step 6: Open firewall ports for Kubernetes
echo "Opening firewall ports"
sudo firewall-cmd --zone=public --permanent --add-port=6443/tcp
sudo firewall-cmd --zone=public --permanent --add-port=2379-2380/tcp
sudo firewall-cmd --zone=public --permanent --add-port=10250/tcp
sudo firewall-cmd --zone=public --permanent --add-port=10251/tcp
sudo firewall-cmd --zone=public --permanent --add-port=10252/tcp
sudo firewall-cmd --zone=public --permanent --add-port=10255/tcp
sudo firewall-cmd --zone=public --permanent --add-port=5473/tcp

# (Option) Stop firewall (this might depend on the security policy of your environment)
systemctl stop firewalld
# Reload firewall
sudo firewall-cmd --reload

# Step 7: Install Kubernetes components
echo "Installing Kubernetes components"

# Import Kubernetes and flannel images into containerd
echo "#----> Import Images for Kubernetes:"
ctr -n k8s.io image import $PATH/images/pause:3.10.tar
ctr -n k8s.io image import $PATH/images/pause_3.6.tar
ctr -n k8s.io image import $PATH/images/controller_v1.8.1.tar
ctr -n k8s.io image import $PATH/images/coredns:v1.11.3.tar
ctr -n k8s.io image import $PATH/images/etcd:3.5.15-0.tar
ctr -n k8s.io image import $PATH/images/flannel-cni-plugin_v1.1.2.tar
ctr -n k8s.io image import $PATH/images/flannel_v0.22.0.tar
ctr -n k8s.io image import $PATH/images/install_k8s_containerd.sh
ctr -n k8s.io image import $PATH/images/kube-apiserver:v1.31.0.tar
ctr -n k8s.io image import $PATH/images/kube-controller-manager:v1.31.0.tar
ctr -n k8s.io image import $PATH/images/kube-proxy:v1.31.0.tar
ctr -n k8s.io image import $PATH/images/kube-scheduler:v1.31.0.tar
ctr -n k8s.io image import $PATH/images/kube-webhook-certgen_v20230407.tar


# List all imported images
crictl images list

# Install Kubernetes components such as kubeadm, kubelet, kubectl
echo "#----> Installing kubeadm:"
yum install -y \
    $PATH/rpm/libnetfilter_cthelper-1.0.0-22.el9.x86_64.rpm  \
    $PATH/rpm/libnetfilter_cttimeout-1.0.0-19.el9.x86_64.rpm  \
    $PATH/rpm/libnetfilter_queue-1.0.5-1.el9.x86_64.rpm  \
    $PATH/rpm/cri-tools-1.31.1-150500.1.1.x86_64.rpm  \
    $PATH/rpm/conntrack-tools-1.4.7-2.el9.x86_64.rpm  \
    $PATH/rpm/kubernetes-cni-1.5.1-150500.1.1.x86_64.rpm  \
    $PATH/rpm/kubelet-1.31.1-150500.1.1.x86_64.rpm  \
    $PATH/rpm/kubectl-1.31.1-150500.1.1.x86_64.rpm  \
    $PATH/rpm/kubeadm-1.31.1-150500.1.1.x86_64.rpm  \
    $PATH/rpm/libnftnl-1.2.6-4.el9_4.x86_64.rpm


# Enable kubelet
sudo systemctl enable --now kubelet.service

# Step 8: Initialize Kubernetes control plane
echo "Initializing Kubernetes control plane"
sudo kubeadm config images pull
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Configure kubectl for the root user
echo "Setting up kubectl configuration"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Deploy Calico network
echo "Deploying Calico network"
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml
sed -i 's/cidr: 192\.168\.0\.0\/16/cidr: 10.244.0.0\/16/g' custom-resources.yaml
kubectl create -f custom-resources.yaml

# Step 9: Join Worker Nodes
echo "To join worker nodes, run the following on the master node to get the join command:"
sudo kubeadm token create --print-join-command

echo "Kubernetes setup is complete!"
