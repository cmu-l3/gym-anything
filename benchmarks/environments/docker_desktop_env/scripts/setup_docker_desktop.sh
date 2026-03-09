#!/bin/bash
# Docker Desktop Setup Script (post_start hook)
# Launches Docker Desktop and configures the environment
#
# Docker Desktop provides a GUI for:
# - Viewing and managing containers
# - Pulling and managing images
# - Docker Compose project management
# - Viewing logs and stats
# - Kubernetes cluster management
# - Docker Hub integration

echo "=== Setting up Docker Desktop Environment ==="

# Wait for desktop to be ready
sleep 5

# Create working directories
echo "Creating working directories..."
mkdir -p /home/ga/Documents/docker-projects
mkdir -p /home/ga/.docker

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
        .docker-icon { font-size: 48px; }
    </style>
</head>
<body>
    <div class="docker-icon">🐳</div>
    <h1>Welcome to Docker Desktop!</h1>
    <p>This is a sample nginx container managed by Docker Desktop.</p>
    <p>If you can see this page, Docker Desktop is working correctly!</p>
    <hr>
    <p><strong>Container:</strong> nginx:alpine</p>
    <p><strong>Port:</strong> 8080 → 80</p>
</body>
</html>
INDEXHTML

chown -R ga:ga /home/ga/Documents/docker-projects

# Accept Docker Desktop terms (create settings file)
echo "Configuring Docker Desktop settings..."
mkdir -p /home/ga/.docker/desktop
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

# Script to check Docker Desktop status
cat > /usr/local/bin/docker-desktop-status << 'STATUSEOF'
#!/bin/bash
# Check Docker Desktop status
echo "=== Docker Desktop Status ==="

# Check if Docker Desktop process is running
if pgrep -f "com.docker.backend" > /dev/null || pgrep -f "/opt/docker-desktop/Docker" > /dev/null; then
    echo "Docker Desktop: RUNNING"
else
    echo "Docker Desktop: NOT RUNNING"
fi

# Check Docker daemon
if docker info > /dev/null 2>&1; then
    echo "Docker Daemon: RUNNING"
    echo ""
    echo "Docker version: $(docker --version)"
    echo "Containers: $(docker ps -q | wc -l) running, $(docker ps -aq | wc -l) total"
    echo "Images: $(docker images -q | wc -l)"
else
    echo "Docker Daemon: NOT RUNNING"
fi
STATUSEOF
chmod +x /usr/local/bin/docker-desktop-status

# Script to list containers with details
cat > /usr/local/bin/list-containers << 'LISTEOF'
#!/bin/bash
# List Docker containers with details
echo "=== Docker Containers ==="
docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
LISTEOF
chmod +x /usr/local/bin/list-containers

# Script to list images
cat > /usr/local/bin/list-images << 'IMAGESEOF'
#!/bin/bash
# List Docker images
echo "=== Docker Images ==="
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"
IMAGESEOF
chmod +x /usr/local/bin/list-images

# Start Docker Desktop for the ga user using systemctl --user
echo "Starting Docker Desktop..."

# Docker Desktop uses systemd user service
# First, enable lingering for the user so user services can run
loginctl enable-linger ga 2>/dev/null || true

# Set up XDG_RUNTIME_DIR for user services
mkdir -p /run/user/1000
chown ga:ga /run/user/1000
chmod 700 /run/user/1000

# Start Docker Desktop via command line (as user ga)
su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"

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
    # Also check if the process is running
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

    # Dismiss any welcome dialogs, subscription agreement, and sign-in prompts
    echo "Dismissing initial dialogs (subscription, sign-in, walkthroughs)..."
    sleep 3

    # Function to dismiss dialogs by clicking known button locations
    dismiss_dialogs() {
        # Press Escape multiple times to close any modal dialogs
        for i in 1 2 3; do
            DISPLAY=:1 xdotool key Escape 2>/dev/null || true
            sleep 0.5
        done

        # Look for and click "Accept" button on subscription agreement (usually bottom-right area)
        # Coordinates are approximate for 1920x1080 resolution
        DISPLAY=:1 xdotool mousemove 960 600 click 1 2>/dev/null || true
        sleep 1

        # Look for and click "Skip" or "Continue without signing in" on sign-in dialog
        # Try clicking "Skip" button area (usually at bottom of sign-in dialog)
        DISPLAY=:1 xdotool mousemove 960 650 click 1 2>/dev/null || true
        sleep 1

        # Press Tab and Enter to navigate and accept dialogs
        DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true
        sleep 0.5

        # Press Escape again to close any remaining popups
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 0.5
    }

    # Run dialog dismissal multiple times to handle cascading dialogs
    dismiss_dialogs
    sleep 2
    dismiss_dialogs
    sleep 2

    # Click on Containers in sidebar to ensure we're at a known state
    # Containers is typically at y=113 in the sidebar (scaled for 1920x1080)
    DISPLAY=:1 xdotool mousemove 130 113 click 1 2>/dev/null || true
    sleep 1

    # Close any "Walkthroughs" popup that may appear (X button usually at top-right of popup)
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5

    echo "Initial dialog handling complete"
else
    echo "WARNING: Docker Desktop window not detected after timeout"
    echo "Docker Desktop may still be starting in the background"
    echo "Check /tmp/docker-desktop.log for details"
fi

# Wait for Docker daemon to be ready (Docker Desktop starts its own daemon)
echo "Waiting for Docker daemon..."
DOCKER_READY=false
for i in {1..60}; do
    if docker info > /dev/null 2>&1; then
        DOCKER_READY=true
        echo "Docker daemon ready after ${i}s"
        break
    fi
    sleep 2
done

if [ "$DOCKER_READY" = true ]; then
    # Pull some basic images that might be useful for tasks
    echo "Pre-pulling common Docker images..."
    docker pull hello-world:latest 2>/dev/null || true
    docker pull alpine:latest 2>/dev/null || true
    docker pull nginx:alpine 2>/dev/null || true
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
