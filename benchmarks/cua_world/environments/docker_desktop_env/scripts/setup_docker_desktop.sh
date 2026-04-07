#!/bin/bash
# Docker Desktop Setup Script (post_start hook)
# Launches Docker Desktop and configures the environment

echo "=== Setting up Docker Desktop Environment ==="

# Wait for desktop to be ready
sleep 5

# Create working directories
echo "Creating working directories..."
mkdir -p /home/ga/Documents/docker-projects
mkdir -p /home/ga/.docker/desktop

# Set ownership
chown -R ga:ga /home/ga/Documents/docker-projects
chown -R ga:ga /home/ga/.docker

# Create a sample docker-compose project for testing
echo "Creating sample Docker Compose project..."
mkdir -p /home/ga/Documents/docker-projects/sample-web-app

cat > /home/ga/Documents/docker-projects/sample-web-app/docker-compose.yml << 'COMPOSEYML'
# Sample Docker Compose file for testing Docker Desktop
# This creates a simple nginx web server

services:
  web:
    image: nginx:alpine
    container_name: sample-nginx
    ports:
      - "8080:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
    restart: unless-stopped
    labels:
      - "com.docker.compose.project=sample-web-app"

  redis:
    image: redis:alpine
    container_name: sample-redis
    ports:
      - "6379:6379"
    restart: unless-stopped
    labels:
      - "com.docker.compose.project=sample-web-app"
COMPOSEYML

# Create sample HTML content
mkdir -p /home/ga/Documents/docker-projects/sample-web-app/html
cat > /home/ga/Documents/docker-projects/sample-web-app/html/index.html << 'INDEXHTML'
<!DOCTYPE html>
<html>
<head>
    <title>Docker Desktop Sample App</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        h1 { color: #2496ed; }
    </style>
</head>
<body>
    <h1>Welcome to Docker Desktop!</h1>
    <p>This is a sample nginx container managed by Docker Desktop.</p>
    <p>If you can see this page, Docker Desktop is working correctly!</p>
    <hr>
    <p><strong>Container:</strong> nginx:alpine</p>
    <p><strong>Port:</strong> 8080 -> 80</p>
</body>
</html>
INDEXHTML

chown -R ga:ga /home/ga/Documents/docker-projects

# Pre-create Docker Desktop settings files to minimize dialogs
echo "Configuring Docker Desktop settings..."

# settings-store.json is the actual config file Docker Desktop reads (PascalCase keys)
cat > /home/ga/.docker/desktop/settings-store.json << 'SETTINGSSTOREJSON'
{
  "AnalyticsEnabled": false,
  "AutoPauseTimeoutSeconds": 300,
  "AutoStart": false,
  "Cpus": 4,
  "DisplayedOnboarding": true,
  "EnableCLIHints": true,
  "EnableDockerAI": true,
  "ExtensionsEnabled": true,
  "KernelForUDP": true,
  "KubernetesEnabled": false,
  "LicenseTermsVersion": 2,
  "NetworkType": "gvisor",
  "OnlyMarketplaceExtensions": true,
  "ProxyEnableKerberosNTLM": false,
  "SettingsVersion": 43,
  "ThemeSource": "system",
  "UseBackgroundIndexing": false,
  "UseCredentialHelper": true,
  "UseVpnkit": false
}
SETTINGSSTOREJSON

# settings.json (legacy/alternative config with camelCase keys)
cat > /home/ga/.docker/desktop/settings.json << 'SETTINGSJSON'
{
  "analyticsEnabled": false,
  "autoStart": false,
  "displayedWelcomeWizard": true,
  "displayedTutorial": true,
  "settingsVersion": 12,
  "extensionsEnabled": true,
  "extensionsMarketplaceEnabled": true,
  "licenseTermsVersion": 2,
  "themeSource": "system",
  "useCredentialHelper": true,
  "kubernetesEnabled": false
}
SETTINGSJSON

chown -R ga:ga /home/ga/.docker

# Create desktop shortcut for Docker Desktop
echo "Creating desktop shortcuts..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/docker-desktop.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Docker Desktop
Comment=Docker Desktop for Linux
Exec=/opt/docker-desktop/bin/docker-desktop
Icon=/opt/docker-desktop/share/icons/hicolor/512x512/apps/docker-desktop.png
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;System;
DESKTOPEOF
chmod +x /home/ga/Desktop/docker-desktop.desktop
chown ga:ga /home/ga/Desktop/docker-desktop.desktop

# Create utility scripts
echo "Creating utility scripts..."

cat > /usr/local/bin/docker-desktop-status << 'STATUSEOF'
#!/bin/bash
echo "=== Docker Desktop Status ==="
if pgrep -f "com.docker.backend" > /dev/null || pgrep -f "/opt/docker-desktop/Docker" > /dev/null; then
    echo "Docker Desktop: RUNNING"
else
    echo "Docker Desktop: NOT RUNNING"
fi
if timeout 5 docker info > /dev/null 2>&1; then
    echo "Docker Daemon: RUNNING"
    echo "Docker version: $(docker --version)"
    echo "Containers: $(docker ps -q | wc -l) running, $(docker ps -aq | wc -l) total"
    echo "Images: $(docker images -q | wc -l)"
else
    echo "Docker Daemon: NOT RUNNING"
fi
STATUSEOF
chmod +x /usr/local/bin/docker-desktop-status

cat > /usr/local/bin/list-containers << 'LISTEOF'
#!/bin/bash
echo "=== Docker Containers ==="
docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
LISTEOF
chmod +x /usr/local/bin/list-containers

cat > /usr/local/bin/list-images << 'IMAGESEOF'
#!/bin/bash
echo "=== Docker Images ==="
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"
IMAGESEOF
chmod +x /usr/local/bin/list-images

# Start Docker Desktop
echo "Starting Docker Desktop..."

# Enable lingering for user services
loginctl enable-linger ga 2>/dev/null || true

# Set up XDG_RUNTIME_DIR
mkdir -p /run/user/1000
chown ga:ga /run/user/1000
chmod 700 /run/user/1000

# Launch Docker Desktop as user ga
su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 setsid /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"

# Wait for Docker Desktop window to appear
echo "Waiting for Docker Desktop to start..."
sleep 10

DOCKER_DESKTOP_STARTED=false
for i in {1..90}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "docker"; then
        DOCKER_DESKTOP_STARTED=true
        echo "Docker Desktop window detected after ${i}s"
        break
    fi
    if pgrep -f "com.docker.backend" > /dev/null || pgrep -f "/opt/docker-desktop/Docker" > /dev/null; then
        if [ $((i % 10)) -eq 0 ]; then
            echo "  Docker Desktop process running, waiting for window... (${i}s)"
        fi
    fi
    sleep 1
done

if [ "$DOCKER_DESKTOP_STARTED" = true ]; then
    sleep 5

    # Maximize Docker Desktop window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "docker" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi

    # ============================================================
    # Dialog dismissal for Docker Desktop v4.65+
    # Coordinates are for 1920x1080 resolution.
    # Dialog 1: Subscription Service Agreement -> click "Accept"
    # Dialog 2: Sign In -> click "Skip"
    # ============================================================
    echo "Dismissing initial dialogs (subscription, sign-in)..."
    sleep 3

    # --- Dialog 1: Subscription Service Agreement ---
    # The "Accept" button is at ~(1757, 1043) in 1920x1080
    # Try clicking it multiple times to be safe
    for attempt in 1 2 3; do
        echo "  Subscription dialog dismissal attempt $attempt..."
        DISPLAY=:1 xdotool mousemove 1757 1043 click 1 2>/dev/null || true
        sleep 2
        # Also try Tab+Enter as fallback for keyboard navigation
        DISPLAY=:1 xdotool key Tab Return 2>/dev/null || true
        sleep 1
    done

    # --- Dialog 2: Sign In -> Skip ---
    # The "Skip" link is at ~(1223, 254) in 1920x1080
    sleep 2
    for attempt in 1 2 3; do
        echo "  Sign-in skip attempt $attempt..."
        DISPLAY=:1 xdotool mousemove 1223 254 click 1 2>/dev/null || true
        sleep 2
    done

    # Close any browser windows opened by the dialogs
    DISPLAY=:1 wmctrl -c "Data Processing" 2>/dev/null || true
    DISPLAY=:1 wmctrl -c "Firefox" 2>/dev/null || true
    DISPLAY=:1 wmctrl -c "Chromium" 2>/dev/null || true
    sleep 1

    # Re-focus Docker Desktop after closing browser
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "docker" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi

    # Dismiss any remaining popups (notification banners, walkthroughs)
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5

    # Close the Learning center / Walkthroughs panel if visible
    # X button at ~(1883, 126) in 1920x1080 (from 1280x720: 1255, 84)
    DISPLAY=:1 xdotool mousemove 1883 126 click 1 2>/dev/null || true
    sleep 1

    # Click on Containers in sidebar to ensure known state
    # Containers is at ~(173, 155) in 1920x1080 (from 1280x720: 115, 103)
    DISPLAY=:1 xdotool mousemove 173 155 click 1 2>/dev/null || true
    sleep 1

    # Close the Walkthroughs banner at bottom if visible
    # X button at ~(1698, 861) in 1920x1080 (from 1280x720: 1132, 574)
    DISPLAY=:1 xdotool mousemove 1698 861 click 1 2>/dev/null || true
    sleep 0.5

    echo "Initial dialog handling complete"
else
    echo "WARNING: Docker Desktop window not detected after timeout"
    echo "Docker Desktop may still be starting in the background"
    echo "Check /tmp/docker-desktop.log for details"
fi

# Wait for Docker daemon to be ready
# Docker Desktop's daemon (desktop-linux context) becomes available after dialogs are accepted.
# We also check the default Docker Engine context as fallback.
echo "Waiting for Docker daemon..."
DOCKER_READY=false
for i in {1..90}; do
    # Check as ga user (uses desktop-linux context after Docker Desktop starts)
    if su - ga -c "timeout 5 docker info > /dev/null 2>&1"; then
        DOCKER_READY=true
        echo "Docker daemon ready (ga user) after $((i * 2))s"
        break
    fi
    # Also check as root with default context
    if timeout 5 docker info > /dev/null 2>&1; then
        DOCKER_READY=true
        echo "Docker daemon ready (root/default) after $((i * 2))s"
        break
    fi
    if [ $((i % 10)) -eq 0 ]; then
        echo "  Still waiting for Docker daemon... ($((i * 2))s)"
    fi
    sleep 2
done

if [ "$DOCKER_READY" = true ]; then
    # Pull common images (use ga user to go through Docker Desktop's daemon)
    echo "Pre-pulling common Docker images..."
    su - ga -c "docker pull hello-world:latest" 2>/dev/null || docker pull hello-world:latest 2>/dev/null || true
    su - ga -c "docker pull alpine:latest" 2>/dev/null || docker pull alpine:latest 2>/dev/null || true
    su - ga -c "docker pull nginx:alpine" 2>/dev/null || docker pull nginx:alpine 2>/dev/null || true

    # Clean up auto-started welcome-to-docker container (if any)
    su - ga -c "docker stop welcome-to-docker 2>/dev/null; docker rm welcome-to-docker 2>/dev/null" || true
else
    echo "WARNING: Docker daemon not ready after timeout"
    echo "Checking Docker Desktop log for errors..."
    tail -20 /tmp/docker-desktop.log 2>/dev/null || true
fi

echo ""
echo "=== Docker Desktop Setup Complete ==="
echo ""
echo "Docker Desktop is running. Key features:"
echo "  - Containers view: See all running and stopped containers"
echo "  - Images view: Manage Docker images"
echo "  - Volumes view: Manage persistent data"
echo "  - Compose: Run multi-container applications"
echo ""
echo "Sample project: /home/ga/Documents/docker-projects/sample-web-app/"
echo ""
echo "Utility commands:"
echo "  docker-desktop-status  - Check Docker Desktop status"
echo "  list-containers        - List all containers"
echo "  list-images            - List all images"
echo ""
