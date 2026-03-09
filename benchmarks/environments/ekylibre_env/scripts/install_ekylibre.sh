#!/bin/bash
# Ekylibre Installation Script (pre_start hook)
# Installs Docker + tools. Starts Docker image build in background using
# the background-continuation pattern (cross-cutting pattern #23).
# The actual Rails app image build takes 30-50 minutes.

set -e

echo "=== Installing Ekylibre prerequisites ==="

export DEBIAN_FRONTEND=noninteractive

echo "Updating package lists..."
apt-get update

# ============================================================
# 1. Install Docker + Compose v2
# ============================================================
echo "Installing Docker..."
apt-get install -y docker.io docker-compose-v2

systemctl enable docker
systemctl start docker

usermod -aG docker ga || true

# ============================================================
# 2. Install Firefox + UI automation tools
# ============================================================
echo "Installing Firefox and automation tools..."
apt-get install -y \
    firefox \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    scrot \
    imagemagick \
    curl \
    jq \
    git \
    wget \
    ca-certificates \
    netcat-openbsd \
    python3 \
    python3-pip

pip3 install --no-cache-dir requests >/dev/null 2>&1 || true

apt-get clean
rm -rf /var/lib/apt/lists/*

# ============================================================
# 3. Set up working directory
# ============================================================
echo "Setting up Ekylibre working directory..."
EKYLIBRE_DIR="/home/ga/ekylibre"
mkdir -p "$EKYLIBRE_DIR"

# Copy Docker config files from mount
cp /workspace/config/docker-compose.yml "$EKYLIBRE_DIR/"
cp /workspace/config/Dockerfile         "$EKYLIBRE_DIR/"
cp /workspace/config/.env               "$EKYLIBRE_DIR/"
cp /workspace/config/.dockerhub_credentials "$EKYLIBRE_DIR/" 2>/dev/null || true
# proj_epsg.txt is COPY'd into the Docker image by the Dockerfile to /usr/share/proj/epsg
# (PROJ 7.x removed the text-format epsg file that rgeo-proj4 gem requires)
cp /workspace/config/proj_epsg.txt      "$EKYLIBRE_DIR/"

chown -R ga:ga "$EKYLIBRE_DIR"

# ============================================================
# 4. Authenticate with Docker Hub (avoid rate limits - pattern #8)
# ============================================================
if [ -f "$EKYLIBRE_DIR/.dockerhub_credentials" ]; then
    echo "Authenticating with Docker Hub..."
    source "$EKYLIBRE_DIR/.dockerhub_credentials"
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || true
fi

# ============================================================
# 5. Pre-pull base images (so they're cached for the build)
# ============================================================
echo "Pre-pulling base Docker images..."
docker pull ruby:2.7.8-slim &
docker pull postgis/postgis:13-3.4 &
docker pull redis:5.0-alpine &
wait
echo "Base images pulled."

# ============================================================
# 6. Start the Ekylibre Docker image build in background
#    Using nohup to detach from the hook process (pattern #23)
# ============================================================
echo "Starting Ekylibre Docker image build in background..."
cat > /tmp/build_ekylibre.sh << 'BUILDBASH'
#!/bin/bash
LOG="/tmp/ekylibre_build.log"
MARKER="/tmp/ekylibre_build_complete.marker"
ERROR_MARKER="/tmp/ekylibre_build_error.marker"

echo "[$(date)] Starting Ekylibre Docker image build..." > "$LOG"

cd /home/ga/ekylibre

# Build the image
if docker build -t ekylibre-app:local . >> "$LOG" 2>&1; then
    echo "[$(date)] Ekylibre Docker image built successfully." >> "$LOG"
    touch "$MARKER"
else
    echo "[$(date)] ERROR: Ekylibre Docker image build FAILED!" >> "$LOG"
    touch "$ERROR_MARKER"
fi
BUILDBASH

chmod +x /tmp/build_ekylibre.sh
nohup bash /tmp/build_ekylibre.sh > /tmp/build_ekylibre_wrapper.log 2>&1 &

echo "Docker image build started in background (PID: $!)"
echo "Build log: /tmp/ekylibre_build.log"
echo ""
echo "=== Installation step complete ==="
echo "Docker: $(docker --version 2>/dev/null || echo 'installed')"
echo "Docker Compose: $(docker compose version 2>/dev/null || echo 'installed')"
echo "Background build of Ekylibre Docker image in progress..."
echo "post_start will wait for build completion before proceeding."
