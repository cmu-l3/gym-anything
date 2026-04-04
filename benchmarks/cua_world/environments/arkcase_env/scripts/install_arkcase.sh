#!/bin/bash
# pre_start hook: Install K3s (lightweight Kubernetes), Helm, and required tools
set -e

echo "=== Installing ArkCase dependencies (pre_start) ==="
export DEBIAN_FRONTEND=noninteractive

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

echo "=== ArkCase dependencies installation complete ==="
