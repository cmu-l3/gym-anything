#!/bin/bash
# pre_start hook: Install K3s (lightweight Kubernetes), Helm, and required tools
# NOTE: set -e removed - many steps can fail gracefully

echo "=== Installing ArkCase dependencies (pre_start) ==="
export DEBIAN_FRONTEND=noninteractive

# ── 0. Create swap file to prevent OOM during heavy Helm deploys ──────────────
# ArkCase K3s + 10 pods can consume nearly all 16GB; swap prevents sshd from being OOM-killed
if [ ! -f /swapfile ]; then
    echo "Creating 8GB swap file..."
    if fallocate -l 8G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=8192 2>/dev/null; then
        chmod 600 /swapfile
        mkswap /swapfile && swapon /swapfile
        echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
        echo "Swap enabled: $(swapon --show)"
    else
        echo "WARNING: Could not create swap file (insufficient disk space?), continuing without swap"
        rm -f /swapfile 2>/dev/null
    fi
else
    swapon /swapfile 2>/dev/null || true
    echo "Swap already exists: $(swapon --show)"
fi

# ── 1. System packages ────────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y \
    curl wget jq git unzip \
    firefox \
    wmctrl xdotool x11-utils xclip \
    scrot imagemagick \
    libnss3-tools openssl \
    python3-pip python3-requests \
    net-tools dnsutils \
    ca-certificates gnupg lsb-release

# ── 2. Install K3s (lightweight Kubernetes) ────────────────────────────────────
echo "=== Installing K3s ==="
# Install K3s without traefik (we'll configure ingress separately)
# INSTALL_K3S_EXEC sets K3s flags: disable traefik since we'll use NodePort
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik --write-kubeconfig-mode=644" sh -

# CRITICAL: Restore iptables FORWARD policy to ACCEPT.
# K3s/flannel sets FORWARD policy to DROP for pod networking. This breaks
# QEMU's user-mode networking SSH port forwarding. Restoring ACCEPT allows
# both pod networking (via specific FORWARD rules) and QEMU port forwarding.
sleep 5
iptables -P FORWARD ACCEPT 2>/dev/null || true
echo "iptables FORWARD policy restored to ACCEPT"

# Verify K3s binary is installed
ls -la /usr/local/bin/k3s

# Wait for K3s to create the kubeconfig
echo "Waiting for K3s kubeconfig to be created..."
for i in $(seq 1 60); do
    if [ -f /etc/rancher/k3s/k3s.yaml ]; then
        echo "K3s kubeconfig found after ${i}s"
        break
    fi
    sleep 2
done

# Copy kubeconfig to a standard location for all users
mkdir -p /home/ga/.kube /root/.kube
if [ -f /etc/rancher/k3s/k3s.yaml ]; then
    cp /etc/rancher/k3s/k3s.yaml /home/ga/.kube/config
    cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
    chown -R ga:ga /home/ga/.kube
    chmod 600 /home/ga/.kube/config /root/.kube/config
    echo "Kubeconfig copied successfully"
else
    echo "WARNING: K3s kubeconfig not found yet, will be set up in post_start"
fi

# ── 3. Install Helm ──────────────────────────────────────────────────────────
echo "=== Installing Helm ==="
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

# ── 4. Install kubectl (already bundled with K3s but create alias) ──────────
# K3s installs kubectl at /usr/local/bin/kubectl
kubectl version --client 2>/dev/null || ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

# ── 5. Add ArkCase Helm repository ──────────────────────────────────────────
echo "=== Adding ArkCase Helm repo ==="
helm repo add arkcase https://arkcase.github.io/ark_helm_charts/ || true
helm repo update

# ── 6. Configure ECR public registry auth for K3s (avoids rate limiting) ────
# AWS ECR public rate-limits unauthenticated pulls aggressively (500GB/month).
# Authenticated pulls get 5TB/month. Configure K3s with ECR auth if available.
echo "=== Configuring ECR public registry auth ==="

ECR_TOKEN=""

# Method 1: Check if a pre-generated token was mounted at /workspace/config/ecr_token
if [ -f /workspace/config/ecr_token ] && [ -s /workspace/config/ecr_token ]; then
    ECR_TOKEN=$(cat /workspace/config/ecr_token)
    echo "ECR token loaded from /workspace/config/ecr_token"
fi

# Method 2: Try aws-cli if available (needs credentials)
if [ -z "$ECR_TOKEN" ]; then
    pip3 install --no-cache-dir --break-system-packages awscli 2>/dev/null || \
        pip3 install --no-cache-dir awscli 2>/dev/null || true
    if command -v aws >/dev/null 2>&1; then
        ECR_TOKEN=$(aws ecr-public get-login-password --region us-east-1 2>/dev/null || echo "")
    fi
fi

if [ -n "$ECR_TOKEN" ]; then
    echo "ECR auth token obtained, configuring K3s registries..."
    mkdir -p /etc/rancher/k3s
    cat > /etc/rancher/k3s/registries.yaml << REGEOF
mirrors:
  "public.ecr.aws":
    endpoint:
      - "https://public.ecr.aws"
configs:
  "public.ecr.aws":
    auth:
      username: AWS
      password: "${ECR_TOKEN}"
REGEOF
    chmod 600 /etc/rancher/k3s/registries.yaml
    echo "ECR registry auth configured for K3s"
    # Restart K3s to pick up registry config
    systemctl restart k3s 2>/dev/null || true
    sleep 10
    # Restore iptables after K3s restart
    iptables -P FORWARD ACCEPT 2>/dev/null || true
else
    echo "WARNING: Could not get ECR auth token. Image pulls may be rate-limited."
fi

# ── 7. Pre-pull critical ArkCase images (with retry) ─────────────────────────
# Pre-pulling during install spreads the load and survives rate limits better
# than pulling all images simultaneously during Helm deploy.
echo "=== Pre-pulling ArkCase container images ==="
IMAGES="
public.ecr.aws/arkcase/deployer:latest
public.ecr.aws/arkcase/nettest:latest
public.ecr.aws/arkcase/setperm:latest
public.ecr.aws/arkcase/base:latest
public.ecr.aws/arkcase/samba:latest
public.ecr.aws/arkcase/postgres:13
public.ecr.aws/arkcase/solr:8.11.4
public.ecr.aws/arkcase/zookeeper:3.8.6
public.ecr.aws/arkcase/step-ca:0.29.0
public.ecr.aws/arkcase/haproxy:2.6
public.ecr.aws/arkcase/artemis:2.44.0
public.ecr.aws/arkcase/minio:20251015172955.0.0
public.ecr.aws/arkcase/dbinit:1.2.0
public.ecr.aws/arkcase/core:3.0.0
public.ecr.aws/arkcase/artifacts-core:25.09.00
"

# Wait for K3s containerd to be available
for i in $(seq 1 30); do
    if crictl version >/dev/null 2>&1; then
        echo "containerd ready"
        break
    fi
    sleep 2
done

PULLED=0
FAILED=0
for img in $IMAGES; do
    [ -z "$img" ] && continue
    echo "Pulling: $img"
    # Try up to 3 times with backoff
    for attempt in 1 2 3; do
        if crictl pull "$img" 2>/dev/null; then
            echo "  OK: $img"
            PULLED=$((PULLED + 1))
            break
        fi
        if [ $attempt -lt 3 ]; then
            echo "  Retry $attempt for $img (waiting 15s)..."
            sleep 15
        else
            echo "  FAILED: $img (will retry during Helm deploy)"
            FAILED=$((FAILED + 1))
        fi
    done
done
echo "Pre-pull complete: $PULLED succeeded, $FAILED failed"

echo "=== ArkCase dependencies installation complete ==="
