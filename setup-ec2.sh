#!/usr/bin/env bash
# ==============================================================================
# MedCare DevSecOps & Kubernetes Lab Automation Setup Script
# Target OS: Ubuntu 24.04 LTS (AWS EC2)
# Lab Experiments: Exp 7 (Docker + K8s), Exp 8 (Blue-Green), Exp 9 (DevSecOps)
# ==============================================================================

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "===================================================================="
echo " Starting Automated DevSecOps & K3s Kubernetes Setup for EC2"
echo "===================================================================="

# 1. Update system packages and install prerequisites
echo "[Step 1/7] Updating package index and installing core utilities..."
sudo apt-get update -y
sudo apt-get install -y \
    curl \
    wget \
    gnupg \
    lsb-release \
    apt-transport-https \
    ca-certificates \
    git \
    openjdk-17-jdk \
    docker.io

# 2. Configure Docker daemon & permissions
echo "[Step 2/7] Configuring Docker service and user permissions..."
sudo systemctl enable docker
sudo systemctl start docker

# Add ubuntu user to docker group if present
if id "ubuntu" &>/dev/null; then
    sudo usermod -aG docker ubuntu
fi

# 3. Install Jenkins LTS
echo "[Step 3/7] Installing Jenkins LTS..."
sudo mkdir -p /usr/share/keyrings
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y jenkins

# Add jenkins user to docker group
sudo usermod -aG docker jenkins

# 4. Install Aqua Security Trivy (Vulnerability, Secret, and Misconfig Scanner)
echo "[Step 4/7] Installing Aqua Security Trivy..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor --batch --yes -o /etc/apt/keyrings/trivy.gpg
echo "deb [signed-by=/etc/apt/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list

sudo apt-get update -y
if ! sudo apt-get install -y trivy; then
    echo "Apt package repository fallback: Installing Trivy via official install script..."
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin
fi

# 5. Install lightweight Kubernetes (K3s) with 644 kubeconfig
echo "[Step 5/7] Installing K3s Kubernetes Cluster..."
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -

# Wait for K3s kubeconfig to generate
echo "Waiting for K3s cluster initialization..."
until [ -f /etc/rancher/k3s/k3s.yaml ]; do
    sleep 2
done

# Ensure kubectl is accessible in PATH
if [ ! -f /usr/local/bin/kubectl ] && [ -f /usr/local/bin/k3s ]; then
    sudo ln -s /usr/local/bin/k3s /usr/local/bin/kubectl
fi

# 6. Configure Passwordless Sudo & Kubernetes Credentials for Jenkins
echo "[Step 6/7] Granting permissions to Jenkins user for K8s image importing..."
echo "jenkins ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/jenkins
sudo chmod 0440 /etc/sudoers.d/jenkins

# Setup Kubeconfig for Jenkins
sudo mkdir -p /var/lib/jenkins/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /var/lib/jenkins/.kube/config
sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube
sudo chmod 600 /var/lib/jenkins/.kube/config

# Setup Kubeconfig for ubuntu user as well
if [ -d "/home/ubuntu" ]; then
    mkdir -p /home/ubuntu/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
    sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube
    chmod 600 /home/ubuntu/.kube/config
fi

# 7. Restart Jenkins service to apply group & path updates
echo "[Step 7/7] Restarting Jenkins service..."
sudo systemctl daemon-reload
sudo systemctl restart jenkins
sudo systemctl enable jenkins

# Wait for initial admin password file
echo "Waiting for Jenkins to finish initialization..."
for i in {1..30}; do
    if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
        break
    fi
    sleep 2
done

# Fetch public IPv4 address
PUBLIC_IP=$(curl -s --connect-timeout 3 http://checkip.amazonaws.com 2>/dev/null || \
            curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || \
            curl -s --connect-timeout 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || \
            hostname -I | awk '{print $1}')

INITIAL_PASS=""
if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
    INITIAL_PASS=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)
else
    INITIAL_PASS="[Please run: sudo cat /var/lib/jenkins/secrets/initialAdminPassword]"
fi

echo ""
echo "===================================================================="
echo " MedCare DevSecOps & Kubernetes Lab Setup Complete!                 "
echo "===================================================================="
echo ""
echo " 1. Jenkins CI/CD Dashboard:"
echo "    URL:                 http://${PUBLIC_IP}:8080"
echo "    Initial Admin Pass:  ${INITIAL_PASS}"
echo ""
echo " 2. Live Kubernetes NodePort Service (After Pipeline Run):"
echo "    URL:                 http://${PUBLIC_IP}:30080"
echo ""
echo " 3. Verify Local Kubernetes Cluster:"
echo "    Command:             kubectl get nodes"
echo "    Command:             kubectl get pods,svc -A"
echo ""
echo "===================================================================="
echo " Next Steps: Follow README.md to configure your Jenkins Pipeline Job!"
echo "===================================================================="
