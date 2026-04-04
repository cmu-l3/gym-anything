#!/bin/bash
set -e
echo "=== Setting up DevOps CI/CD Pipeline Viz Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Desktop /home/ga/Diagrams

# Clean up any previous runs
rm -f /home/ga/Diagrams/pipeline_diagram.drawio
rm -f /home/ga/Diagrams/pipeline_diagram.png

# Create the Jenkinsfile with realistic Groovy syntax
# This file contains the logic the agent must visualize
cat > /home/ga/Desktop/project_pipeline.jenkinsfile << 'EOF'
pipeline {
    agent any
    
    environment {
        REGISTRY = "registry.example.com"
        APP_NAME = "payment-service"
    }
    
    stages {
        stage('Source Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Compile & Build') {
            steps {
                echo "Compiling Java artifacts..."
                # Agent must identify 'mvn' as Maven
                sh 'mvn clean package -DskipTests'
            }
        }
        
        stage('Verification Strategy') {
            # Agent must identify this as Parallel execution
            parallel {
                stage('Unit Testing') {
                    steps {
                        sh 'mvn test'
                    }
                }
                stage('Integration Testing') {
                    steps {
                        sh 'mvn verify -Pintegration'
                    }
                }
            }
        }
        
        stage('Code Quality') {
            steps {
                script {
                    # Agent must identify 'sonar-scanner' as SonarQube
                    sh 'sonar-scanner -Dsonar.projectKey=payment-service'
                }
            }
        }
        
        stage('Containerize') {
            steps {
                # Agent must identify 'docker'
                sh 'docker build -t ${REGISTRY}/${APP_NAME}:${BUILD_NUMBER} .'
                sh 'docker push ${REGISTRY}/${APP_NAME}:${BUILD_NUMBER}'
            }
        }
        
        stage('Production Rollout') {
            # Agent must identify Conditional logic (Main branch only)
            when {
                branch 'main'
            }
            steps {
                # Agent must identify 'kubectl' as Kubernetes
                sh 'kubectl apply -f k8s/deployment.yaml'
                sh 'kubectl rollout status deployment/payment-service'
            }
        }
    }
    
    post {
        failure {
            echo "Pipeline failed!"
            # Agent must identify 'notify-slack' or Slack
            sh './notify-slack.sh --channel=#ops-alerts --message="Build ${BUILD_NUMBER} Failed"'
        }
        success {
            echo "Pipeline succeeded"
        }
    }
}
EOF
chown ga:ga /home/ga/Desktop/project_pipeline.jenkinsfile

# Create Instructions file
cat > /home/ga/Desktop/README.txt << 'EOF'
TASK INSTRUCTIONS
=================

We need to document our legacy Jenkins pipeline for the new onboarding wiki.

1. Open 'project_pipeline.jenkinsfile' on your Desktop and read the logic.
2. Launch diagrams.net (draw.io).
3. Create a flowchart diagram visualizing this pipeline.

IMPORTANT MAPPING RULES:
- Label steps with the ACTUAL TOOL NAME used in the script commands.
  - Example: If you see 'git clone', label the box "Git".
  - Example: If you see 'npm install', label the box "NPM".
  - Do NOT just use the generic stage names like "Verification Strategy".

REQUIRED VISUAL ELEMENTS:
- The sequential flow of stages.
- The PARALLEL execution of the testing stages.
- The CONDITIONAL deployment (indicate it only runs on 'main' branch).
- The FAILURE handler (what happens if it fails).

OUTPUT:
- Save diagram to: ~/Diagrams/pipeline_diagram.drawio
- Export image to: ~/Diagrams/pipeline_diagram.png
EOF
chown ga:ga /home/ga/Desktop/README.txt

# Ensure draw.io is NOT running (agent must launch it)
pkill -f "drawio" || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="