#!/bin/bash

# Step 0: Add hostnames to /etc/hosts
echo "Updating /etc/hosts file"
cat >> /etc/hosts << EOF
# Kubernetes Cluster
x.x.x.x  master    # Replace with your actual hostname and IP address
x.x.x.x worker1   # Replace with your actual hostname and IP address
x.x.x.x  worker2   # Replace with your actual hostname and IP address
EOF

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

# Step 4: Disable Swap
echo "Disabling swap"
sudo swapoff -a
sudo sed -e '/swap/s/^/#/g' -i /etc/fstab

# Step 5: Install Containerd
echo "Installing containerd"
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf makecache
sudo dnf -y install containerd.io

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

# Reload firewall
sudo firewall-cmd --reload

# Step 7: Install Kubernetes components
echo "Installing Kubernetes components"
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# Install kubelet, kubeadm, kubectl
sudo dnf makecache
sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

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
