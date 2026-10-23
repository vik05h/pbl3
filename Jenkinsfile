pipeline {
    agent any

    environment {
        APP_NAME = 'healthcare-app'
        TAG = 'latest'
    }

    stages {
        stage('1. Checkout GitHub') {
            steps {
                echo 'Checking out source repository from GitHub...'
                checkout scm
            }
        }

        stage('2. DevSecOps Healthcare Audit (Exp 9)') {
            steps {
                echo 'Executing Aqua Trivy DevSecOps Security Scan (Vulnerabilities, Secrets, Misconfigurations)...'
                sh 'trivy fs --scanners vuln,secret,misconfig --exit-code 0 .'
            }
        }

        stage('3. Build Docker & Load to K8s (Exp 7)') {
            steps {
                echo 'Building Docker image for MedCare Healthcare Application...'
                sh 'docker build -t healthcare-app:latest .'
                echo 'Importing container image into local K3s containerd runtime...'
                sh 'docker save healthcare-app:latest | sudo k3s ctr images import -'
            }
        }

        stage('4. Deploy Blue & Green Pods (Exp 7)') {
            steps {
                echo 'Deploying Blue and Green environments to Kubernetes (K3s)...'
                sh 'kubectl apply -f k8s-blue-green.yaml'
                echo 'Verifying rollout status for Blue deployment...'
                sh 'kubectl rollout status deployment/healthcare-blue --timeout=90s'
                echo 'Verifying rollout status for Green deployment...'
                sh 'kubectl rollout status deployment/healthcare-green --timeout=90s'
            }
        }

        stage('5. Blue-Green Traffic Switch (Exp 8)') {
            steps {
                echo 'Switching live production traffic to GREEN environment (v2.0)...'
                sh 'kubectl patch service healthcare-service -p \'{"spec":{"selector":{"app":"healthcare","version":"green"}}}\''
                echo 'Fetching active cluster pods and NodePort service status...'
                sh 'kubectl get pods,svc -o wide'
            }
        }
    }

    post {
        success {
            echo '========================================================================'
            echo 'SUCCESS: MedCare Blue-Green Zero-Downtime Deployment & DevSecOps Complete!'
            echo 'Access the live application at http://<EC2_PUBLIC_IP>:30080'
            echo '========================================================================'
        }
        failure {
            echo '========================================================================'
            echo 'FAILURE: Pipeline encountered errors. Please inspect stage execution logs.'
            echo '========================================================================'
        }
    }
}
