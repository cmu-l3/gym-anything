#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Remediate Infrastructure as Code Task ==="

WORKSPACE_DIR="/home/ga/workspace/platform_infra"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create subdirectories
sudo -u ga mkdir -p "$WORKSPACE_DIR/docker"
sudo -u ga mkdir -p "$WORKSPACE_DIR/kubernetes"
sudo -u ga mkdir -p "$WORKSPACE_DIR/terraform"
sudo -u ga mkdir -p "$WORKSPACE_DIR/nginx"
sudo -u ga mkdir -p "$WORKSPACE_DIR/.github/workflows"

# ─── docker/Dockerfile ────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/docker/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "4", "app:create_app()"]
EOF

# ─── docker/docker-compose.yml ────────────────────────────────────────
cat > "$WORKSPACE_DIR/docker/docker-compose.yml" << 'DCEOF'
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://appuser:SuperSecret123!@db:5432/platform_db
      - REDIS_URL=redis://cache:6379/0
      - SECRET_KEY=my-super-secret-key-12345
    depends_on:
      - db
      - cache
    restart: unless-stopped

  db:
    image: postgres:15-alpine
    environment:
      # Database configuration
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: "SuperSecret123!"
      POSTGRES_DB: platform_db
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  cache:
    image: redis:7-alpine
    ports:
      - "6379:6379"

volumes:
  postgres_data:
DCEOF

# ─── kubernetes/deployment.yaml ───────────────────────────────────────
cat > "$WORKSPACE_DIR/kubernetes/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: platform-api
  namespace: production
  labels:
    app: platform-api
    version: v2.1.0
spec:
  replicas: 3
  selector:
    matchLabels:
      app: platform-api
  template:
    metadata:
      labels:
        app: platform-api
        version: v2.1.0
    spec:
      containers:
        - name: api
          image: registry.company.com/platform-api:2.1.0
          ports:
            - containerPort: 8000
              protocol: TCP
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: platform-secrets
                  key: database-url
            - name: REDIS_URL
              value: "redis://redis-service:6379/0"
      imagePullSecrets:
        - name: registry-credentials
EOF

# ─── kubernetes/service.yaml (correct) ───────────────────────────────
cat > "$WORKSPACE_DIR/kubernetes/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: platform-api-service
  namespace: production
spec:
  selector:
    app: platform-api
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8000
  type: ClusterIP
EOF

# ─── kubernetes/ingress.yaml (correct) ───────────────────────────────
cat > "$WORKSPACE_DIR/kubernetes/ingress.yaml" << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: platform-ingress
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
    - hosts:
        - api.platform.company.com
      secretName: platform-tls
  rules:
    - host: api.platform.company.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: platform-api-service
                port:
                  number: 80
EOF

# ─── terraform/main.tf ────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/terraform/main.tf" << 'EOF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "platform-vpc"
    Environment = "production"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "platform-public-subnet"
  }
}

resource "aws_security_group" "app" {
  name        = "platform-app-sg"
  description = "Security group for platform application"
  vpc_id      = aws_vpc.main.id

  # Inbound rules
  ingress {
    description = "Allow all inbound"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "platform-app-sg"
  }
}

resource "aws_instance" "app" {
  ami                    = "ami-0c55b159cbfafe1f0"
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]

  tags = {
    Name        = "platform-app"
    Environment = "production"
  }
}
EOF

# ─── nginx/nginx.conf ─────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/nginx/nginx.conf" << 'EOF'
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent"';

    access_log /var/log/nginx/access.log main;
    error_log  /var/log/nginx/error.log warn;

    sendfile    on;
    tcp_nopush  on;
    keepalive_timeout 65;
    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    upstream app_backend {
        server 127.0.0.1:8000;
    }

    server {
        listen 80;
        server_name api.platform.company.com;
        return 301 https://$server_name$request_uri;
    }

    server {
        listen 443 ssl;
        server_name api.platform.company.com;

        ssl_certificate     /etc/nginx/ssl/platform.crt;
        ssl_certificate_key /etc/nginx/ssl/platform.key;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;

        location / {
            proxy_pass http://app_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /static/ {
            alias /var/www/static/;
            expires 30d;
        }
    }
}
EOF

# ─── .github/workflows/deploy.yml (correct CI/CD) ────────────────────
cat > "$WORKSPACE_DIR/.github/workflows/deploy.yml" << 'GHEOF'
name: Deploy Platform

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build Docker image
        run: docker build -t platform-api:${{ github.sha }} ./docker

      - name: Run tests
        run: docker run platform-api:${{ github.sha }} pytest

      - name: Push to registry
        run: |
          echo "${{ secrets.REGISTRY_PASSWORD }}" | docker login -u "${{ secrets.REGISTRY_USER }}" --password-stdin registry.company.com
          docker push registry.company.com/platform-api:${{ github.sha }}

      - name: Deploy to Kubernetes
        run: |
          kubectl set image deployment/platform-api api=registry.company.com/platform-api:${{ github.sha }} -n production
GHEOF

# ─── Set ownership ────────────────────────────────────────────────────
sudo chown -R ga:ga "$WORKSPACE_DIR"

# ─── Record baseline hashes ──────────────────────────────────────────
md5sum \
  "$WORKSPACE_DIR/docker/Dockerfile" \
  "$WORKSPACE_DIR/docker/docker-compose.yml" \
  "$WORKSPACE_DIR/kubernetes/deployment.yaml" \
  "$WORKSPACE_DIR/terraform/main.tf" \
  "$WORKSPACE_DIR/nginx/nginx.conf" \
  > /tmp/infra_initial_hashes.txt

# ─── Open VSCode ─────────────────────────────────────────────────────
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code --no-sandbox --disable-workspace-trust '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2

# Open the Dockerfile so the agent sees the first issue immediately
su - ga -c "DISPLAY=:1 code --no-sandbox --disable-workspace-trust '$WORKSPACE_DIR/docker/Dockerfile'" || true
sleep 1

focus_vscode_window

echo "=== Remediate Infrastructure as Code Task Setup Complete ==="
echo "Instructions:"
echo "  The infrastructure code at $WORKSPACE_DIR has been flagged by a"
echo "  security audit. Review and fix all misconfigurations across:"
echo "    - docker/Dockerfile"
echo "    - docker/docker-compose.yml"
echo "    - kubernetes/deployment.yaml"
echo "    - terraform/main.tf"
echo "    - nginx/nginx.conf"
echo "  Save all files when done."
