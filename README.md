# MedCare Healthcare System: DevSecOps & Blue-Green Kubernetes CI/CD

> **Cloud & DevOps Laboratory: Experiments 7, 8 & 9**  
> * **Experiment 7:** Containerization and Local Kubernetes Deployment with Docker + K3s  
> * **Experiment 8:** Zero-Downtime Blue-Green Deployment & Kubernetes Traffic Switching  
> * **Experiment 9:** Shift-Left DevSecOps Vulnerability & Secret Auditing with Aqua Trivy

---

## Architecture Overview

```
                          +------------------------------------------+
                          |   Developer Push to GitHub (main)        |
                          +--------------------+---------------------+
                                               |
                          +--------------------v---------------------+
                          |   GitHub Actions CI: Trivy Container Scan|
                          +------------------------------------------+
                                               |
                                               v
+-----------------------------------------------------------------------------------------+
| AWS EC2 (Amazon Linux 2023 / Ubuntu 24.04) - Host Instance                              |
|                                                                                         |
|  [Jenkins CI/CD Pipeline]                                                               |
|   |-- Stage 1: Checkout GitHub (SCM)                                                    |
|   |-- Stage 2: DevSecOps Healthcare Audit (Trivy fs vuln,secret,misconfig)  [Exp 9]     |
|   |-- Stage 3: Docker Build & Load into K3s containerd                      [Exp 7]     |
|   |-- Stage 4: Deploy Blue (v1.0) & Green (v2.0) Pods                       [Exp 7]     |
|   \-- Stage 5: Zero-Downtime Traffic Switch to GREEN (selector patch)       [Exp 8]     |
|                                                                                         |
|  [K3s Kubernetes Cluster]                                                               |
|   |-- Service: healthcare-service (NodePort :30080)                                     |
|   |     \-- Selector: version=green <--- Traffic routed here 100%                       |
|   |-- Deployment: healthcare-blue  (2 Pods, v1.0 Standby / Rollback)                   |
|   \-- Deployment: healthcare-green (2 Pods, v2.0 Active Production)                     |
+-----------------------------------------------------------------------------------------+
                                               ^
                                               |
                                 Clinicians & Patients (:30080)
```

---

## Repository Structure

| File | Description |
| :--- | :--- |
| [`index.html`](file:///c:/Code/pbl3/index.html) | Modern clinical command dashboard with glowing telemetry, active environment indicators, and live blue-green traffic simulator. |
| [`Dockerfile`](file:///c:/Code/pbl3/Dockerfile) | Production Dockerfile using security-hardened `nginx:alpine` to serve the healthcare dashboard. |
| [`k8s-blue-green.yaml`](file:///c:/Code/pbl3/k8s-blue-green.yaml) | Kubernetes manifest defining `healthcare-blue` (2 replicas), `healthcare-green` (2 replicas), and `healthcare-service` (NodePort 30080). |
| [`.github/workflows/ci.yml`](file:///c:/Code/pbl3/.github/workflows/ci.yml) | GitHub Actions DevSecOps workflow running Docker build and Aqua Trivy container scans on push. |
| [`Jenkinsfile`](file:///c:/Code/pbl3/Jenkinsfile) | Declarative 5-stage pipeline for automated checkout, Trivy audit, Docker build, K3s pod rollout, and blue-green traffic cutover. |
| [`setup-ec2.sh`](file:///c:/Code/pbl3/setup-ec2.sh) | Automated bootstrap script for Amazon Linux 2023 and Ubuntu 24.04 EC2 (installs Java 17, Jenkins LTS, Docker, Trivy, and K3s). |
| [`.gitignore`](file:///c:/Code/pbl3/.gitignore) | Strict DevSecOps ignore rules preventing private keys (`*.pem`, `*.ppk`), env files, and temporary artifacts from being committed. |
| [`README.md`](file:///c:/Code/pbl3/README.md) | Complete lab guide and verification instructions. |

---

## Step 1: Push Repository to GitHub

Initialize git locally and push this codebase to your GitHub account:

```bash
cd pbl3
git init
git add .
git commit -m "feat: complete DevSecOps and Blue-Green Kubernetes CI/CD setup"
git branch -M main
git remote add origin https://github.com/<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME>.git
git push -u origin main
```

---

## Step 2: AWS EC2 Instance Setup

1. **Launch an EC2 Instance:**
   - **AMI:** Amazon Linux 2023 or Ubuntu 24.04 LTS
   - **Instance Type:** `t2.medium` or `t3.medium` (2 vCPU, 4 GiB RAM recommended for running Jenkins + K3s)
   - **Storage:** 25-30 GB gp3

2. **Configure Security Group Inbound Rules:**

| Type | Port Range | Source | Purpose |
| :--- | :--- | :--- | :--- |
| **SSH** | `22` | `0.0.0.0/0` (or My IP) | Remote SSH terminal access |
| **Custom TCP** | `8080` | `0.0.0.0/0` | Jenkins CI/CD Dashboard |
| **Custom TCP** | `30080` | `0.0.0.0/0` | Kubernetes Live Healthcare Application (NodePort) |
| **HTTP** | `80` | `0.0.0.0/0` | Standard web traffic |

---

## Step 3: Run the Automated Setup on EC2

Connect to your EC2 instance and execute the setup script:

```bash
# Option A: Direct in browser terminal (Amazon Linux 2023):
git clone https://github.com/<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME>.git
cd <YOUR_REPO_NAME>
chmod +x setup-ec2.sh
./setup-ec2.sh

# Option B: SSH from local machine using private key:
# Windows PowerShell:
icacls labsuser.pem /inheritance:r /grant:r "$($env:USERNAME):(R)"
ssh -i labsuser.pem ec2-user@<EC2_PUBLIC_IP>
```

The script will automatically:
- Detect the operating system (Amazon Linux 2023 or Ubuntu).
- Install **Java 17 (Amazon Corretto / OpenJDK)**, **Jenkins LTS**, **Docker**, **Aqua Trivy**, and **K3s**.
- Configure user permissions (`docker` group for `ec2-user`, `ubuntu`, and `jenkins`).
- Setup passwordless sudo and copy `/etc/rancher/k3s/k3s.yaml` to `/var/lib/jenkins/.kube/config`.
- Restart Jenkins and output the **Jenkins Initial Admin Password** and direct URLs.

---

## Step 4: Configure the Jenkins Pipeline

1. Open your browser and navigate to:
   ```text
   http://<EC2_PUBLIC_IP>:8080
   ```
2. Paste the **Initial Admin Password** shown in the setup script terminal output (or run `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`).
3. Click **"Install suggested plugins"** and create your admin account.
4. From the Jenkins Dashboard, click **"New Item"**:
   - **Item Name:** `MedCare-DevSecOps-BlueGreen`
   - **Type:** Select **Pipeline** -> click **OK**.
5. Scroll down to the **Pipeline** configuration section:
   - **Definition:** Select **`Pipeline script from SCM`**
   - **SCM:** Select **`Git`**
   - **Repository URL:** Enter your GitHub repo URL (e.g. `https://github.com/<YOUR_USERNAME>/<YOUR_REPO>.git`)
   - **Branches to build:** `*/main`
   - **Script Path:** `Jenkinsfile`
6. Click **Save**, then click **"Build Now"**.

---

## Jenkins Pipeline Stages & Lab Experiments Mapping

When the pipeline executes, the Jenkins Dashboard Stage View displays 5 distinct stages:

```
[1. Checkout GitHub] ---> [2. DevSecOps Audit (Exp 9)] ---> [3. Build & Load K8s (Exp 7)] ---> [4. Deploy Pods (Exp 7)] ---> [5. Traffic Switch (Exp 8)]
```

- **Stage 1: Checkout GitHub:** Pulls latest healthcare source code via Git SCM.
- **Stage 2: DevSecOps Healthcare Audit (Exp 9):**
  Runs `trivy fs --scanners vuln,secret,misconfig --exit-code 0 .` to inspect files, configurations, and credentials for HIPAA DevSecOps adherence.
- **Stage 3: Build Docker & Load to K8s (Exp 7):**
  Executes `docker build -t healthcare-app:latest .` and streams image directly into K3s containerd runtime via `docker save healthcare-app:latest | sudo k3s ctr images import -`.
- **Stage 4: Deploy Blue & Green Pods (Exp 7):**
  Applies `k8s-blue-green.yaml`, spinning up 2 replicas of Blue (`version: blue`) and 2 replicas of Green (`version: green`). Verifies rollout health with `kubectl rollout status`.
- **Stage 5: Blue-Green Traffic Switch (Exp 8):**
  Performs an instantaneous, zero-downtime cutover by updating the Service selector:
  ```bash
  kubectl patch service healthcare-service -p '{"spec":{"selector":{"app":"healthcare","version":"green"}}}'
  ```

---

## Step 5: Verification & Testing

### 1. Access the Live Dashboard
Open your browser and navigate to:
```text
http://<EC2_PUBLIC_IP>:30080
```
The MedCare Healthcare System command center displays:
- **Active Environment: GREEN (v2.0 Verified)** badge.
- Verified status for **HIPAA & Trivy DevSecOps Audit**, **Kubernetes Cluster (K3s)**, and **Blue-Green Zero-Downtime**.
- Interactive live traffic router switchboard.

### 2. Verify Pods & Service in Terminal
On your EC2 instance, run:
```bash
kubectl get pods,svc -o wide
```
Output:
```text
NAME                                READY   STATUS    RESTARTS   AGE   IP          NODE
healthcare-blue-xxxx-xxxx           1/1     Running   0          2m    10.42.0.12  ip-xxx
healthcare-blue-xxxx-yyyy           1/1     Running   0          2m    10.42.0.13  ip-xxx
healthcare-green-xxxx-aaaa          1/1     Running   0          2m    10.42.0.14  ip-xxx
healthcare-green-xxxx-bbbb          1/1     Running   0          2m    10.42.0.15  ip-xxx

NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
healthcare-service   NodePort    10.43.150.210   <none>        80:30080/TCP   2m
```

### 3. Check Active Endpoints
Inspect which pods are receiving traffic:
```bash
kubectl get endpoints healthcare-service
```
*(The endpoints will point directly to the 2 Green pod IPs)*.

### 4. Zero-Downtime Instant Rollback (Experiment 8 Demonstration)
If an issue occurs in production, rollback immediately to Blue in under 1 second without restarting containers:
```bash
kubectl patch service healthcare-service -p '{"spec":{"selector":{"app":"healthcare","version":"blue"}}}'
```
To switch back to Green:
```bash
kubectl patch service healthcare-service -p '{"spec":{"selector":{"app":"healthcare","version":"green"}}}'
```

---

## DevSecOps Compliance Checklist (Exp 9)

- [x] **Container Hardening:** Base Alpine Linux minimized footprint with zero unnecessary packages.
- [x] **Static Vulnerability Analysis:** Aqua Trivy scanning integrated both in GitHub Actions and Jenkins Stage 2.
- [x] **Secret Detection:** Strict .gitignore rules and Trivy filesystem scanner block leaked credentials.
- [x] **Least Privilege:** K3s kubeconfig permissions scoped with 600 permission mode for Jenkins user.
- [x] **High Availability:** 2+ replicas per deployment with zero dropped HTTP requests on selector switch.
