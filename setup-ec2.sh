#!/usr/bin/env bash
# ==============================================================================
# MedCare DevSecOps & Kubernetes Lab Automation Setup Script
# Supported OS: Amazon Linux 2023 (ec2-user) & Ubuntu 24.04 LTS (ubuntu)
# Lab Experiments: Exp 7 (Docker + K8s), Exp 8 (Blue-Green), Exp 9 (DevSecOps)
# ==============================================================================

set -euo pipefail

echo "===================================================================="
echo " Starting Automated DevSecOps & K3s Kubernetes Setup for EC2"
echo "===================================================================="

# Detect OS Distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-linux}"
else
    OS_ID="linux"
fi

echo "[OS Detection] Detected Operating System: ${OS_ID}"

# 1. Update system packages and install prerequisites
echo "[Step 1/7] Updating package repositories and installing core packages..."
if [[ "${OS_ID}" =~ (amzn|rhel|centos|fedora) ]]; then
    # Amazon Linux 2023 / RHEL family
    sudo dnf update -y
    # Note: Do not specify 'curl' because 'curl-minimal' is preinstalled on AL2023
    sudo dnf install -y --allowerasing \
        wget \
        git \
        tar \
        gzip \
        docker \
        fontconfig \
        freetype \
        java-17-amazon-corretto-devel || sudo dnf install -y --allowerasing java-17-amazon-corretto
elif [[ "${OS_ID}" =~ (ubuntu|debian) ]]; then
    # Ubuntu / Debian family
    export DEBIAN_FRONTEND=noninteractive
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
fi

# 2. Configure Docker daemon & permissions
echo "[Step 2/7] Configuring Docker service and user permissions..."
sudo systemctl enable docker
sudo systemctl start docker

# Add login users to docker group
for u in "ec2-user" "ubuntu"; do
    if id "$u" &>/dev/null; then
        sudo usermod -aG docker "$u"
        echo "Added user '$u' to docker group."
    fi
done

# 3. Install Jenkins LTS
echo "[Step 3/7] Installing Jenkins LTS..."
if [[ "${OS_ID}" =~ (amzn|rhel|centos|fedora) ]]; then
    sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    sudo dnf upgrade -y --allowerasing
    sudo dnf install -y --allowerasing jenkins
elif [[ "${OS_ID}" =~ (ubuntu|debian) ]]; then
    sudo mkdir -p /usr/share/keyrings
    curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install -y jenkins
fi

# Add jenkins user to docker group
sudo usermod -aG docker jenkins

# 4. Install Aqua Security Trivy (Vulnerability, Secret, and Misconfig Scanner)
echo "[Step 4/7] Installing Aqua Security Trivy..."
if command -v trivy &>/dev/null; then
    echo "Trivy is already installed: $(trivy --version | head -n 1)"
else
    echo "Installing Trivy via official secure installer..."
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin
fi

# Ensure trivy is symlinked to /usr/bin for non-interactive Jenkins shells
if [ -f /usr/local/bin/trivy ] && [ ! -f /usr/bin/trivy ]; then
    sudo ln -sf /usr/local/bin/trivy /usr/bin/trivy
fi

# 5. Install lightweight Kubernetes (K3s) with 644 kubeconfig
echo "[Step 5/7] Installing K3s Kubernetes Cluster..."
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -

# Wait for K3s kubeconfig to generate
echo "Waiting for K3s cluster initialization..."
until [ -f /etc/rancher/k3s/k3s.yaml ]; do
    sleep 2
done

# Ensure kubectl is accessible in /usr/local/bin and /usr/bin
if [ ! -f /usr/local/bin/kubectl ] && [ -f /usr/local/bin/k3s ]; then
    sudo ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
fi
if [ -f /usr/local/bin/kubectl ] && [ ! -f /usr/bin/kubectl ]; then
    sudo ln -sf /usr/local/bin/kubectl /usr/bin/kubectl
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

# Setup Kubeconfig for interactive users (ec2-user or ubuntu)
for u in "ec2-user" "ubuntu"; do
    if [ -d "/home/$u" ]; then
        mkdir -p "/home/$u/.kube"
        sudo cp /etc/rancher/k3s/k3s.yaml "/home/$u/.kube/config"
        sudo chown -R "$u:$u" "/home/$u/.kube"
        chmod 600 "/home/$u/.kube/config"
        echo "Configured ~/.kube/config for $u."
    fi
done

# 7. Restart Jenkins service to apply group & path updates
echo "[Step 7/7] Restarting Jenkins service..."
sudo systemctl daemon-reload
sudo systemctl restart jenkins
sudo systemctl enable jenkins

# Wait for initial admin password file
echo "Waiting for Jenkins initialization to complete..."
for i in {1..35}; do
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
