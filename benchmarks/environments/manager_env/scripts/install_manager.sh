#!/bin/bash
# Manager.io Installation Script (pre_start hook)
# Installs Docker, Firefox, and automation tools.
# Manager.io Server Edition runs as a Docker container on port 8080.
#
# Real sample data: Northwind Traders (official Manager.io sample business)

set -e

echo "=== Installing Manager.io Dependencies ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Docker (docker-compose-plugin not available on all Ubuntu versions)
echo "Installing Docker..."
apt-get install -y docker.io

# Start and enable Docker service
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga

# Install Docker Compose v2 as CLI plugin (docker-compose v1 is incompatible with Docker v26+)
echo "Installing Docker Compose v2..."
COMPOSE_VERSION="v2.24.6"
COMPOSE_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"
mkdir -p /usr/local/lib/docker/cli-plugins/
if wget -q --timeout=120 "$COMPOSE_URL" -O /usr/local/lib/docker/cli-plugins/docker-compose 2>/dev/null; then
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    echo "Docker Compose v2 installed: $(docker compose version 2>/dev/null)"
else
    echo "WARNING: Docker Compose v2 download failed."
fi

# Install Firefox browser for web UI interaction
echo "Installing Firefox..."
apt-get install -y firefox

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    curl \
    wget \
    jq \
    sqlite3 \
    python3-pip \
    python3-requests

# Install Python packages for navigation and verification
pip3 install --no-cache-dir requests selenium 2>/dev/null || \
    pip3 install --no-cache-dir requests 2>/dev/null || true

# Install geckodriver for Selenium-based Firefox navigation
echo "Installing geckodriver..."
GECKODRIVER_VERSION="v0.35.0"
GECKODRIVER_URL="https://github.com/mozilla/geckodriver/releases/download/${GECKODRIVER_VERSION}/geckodriver-${GECKODRIVER_VERSION}-linux64.tar.gz"
if wget -q --timeout=60 "$GECKODRIVER_URL" -O /tmp/geckodriver.tar.gz 2>/dev/null; then
    tar -xzf /tmp/geckodriver.tar.gz -C /usr/local/bin/
    chmod +x /usr/local/bin/geckodriver
    echo "geckodriver installed: $(geckodriver --version 2>/dev/null | head -1)"
    rm -f /tmp/geckodriver.tar.gz
else
    echo "WARNING: geckodriver download failed. Will use xdotool-only navigation."
fi

# Create Manager.io data directory (Docker volume)
echo "Creating Manager.io data directory..."
mkdir -p /home/ga/manager-data
chown ga:ga /home/ga/manager-data

# Download Northwind Traders sample business data
# This is the official Manager.io sample business with realistic accounting data:
# customers, suppliers, inventory items, invoices, receipts, and financial reports.
echo "Downloading Northwind Traders sample data..."
NORTHWIND_DOWNLOADED=false

# Method 1: Official Manager.io CDN (may still be active)
if wget -q --timeout=60 \
    "https://d2ap5zrlkavzl7.cloudfront.net/Northwind.manager" \
    -O /home/ga/manager-data/Northwind.manager 2>/dev/null && \
   [ -s /home/ga/manager-data/Northwind.manager ]; then
    echo "Northwind.manager downloaded from CDN ($(du -h /home/ga/manager-data/Northwind.manager | cut -f1))"
    NORTHWIND_DOWNLOADED=true
fi

# Method 2: Scrape the official guides page for the download link
if [ "$NORTHWIND_DOWNLOADED" = false ]; then
    echo "Trying to scrape download link from Manager.io guides page..."
    GUIDES_PAGE=$(curl -s -L --max-time 30 "https://www2.manager.io/guides/6263" 2>/dev/null || echo "")
    DOWNLOAD_LINK=$(echo "$GUIDES_PAGE" | grep -oP 'href="\K[^"]*Northwind\.manager[^"]*' | head -1)
    if [ -n "$DOWNLOAD_LINK" ]; then
        wget -q --timeout=60 "$DOWNLOAD_LINK" -O /home/ga/manager-data/Northwind.manager 2>/dev/null && \
            [ -s /home/ga/manager-data/Northwind.manager ] && \
            NORTHWIND_DOWNLOADED=true && \
            echo "Northwind.manager downloaded from guides page link"
    fi
fi

# Method 3: Try GitHub raw content (if file is in Manager-io org)
if [ "$NORTHWIND_DOWNLOADED" = false ]; then
    echo "Trying GitHub source..."
    GITHUB_URL="https://raw.githubusercontent.com/Manager-io/Manager/master/Northwind.manager"
    if wget -q --timeout=60 "$GITHUB_URL" \
        -O /home/ga/manager-data/Northwind.manager 2>/dev/null && \
       [ -s /home/ga/manager-data/Northwind.manager ]; then
        echo "Northwind.manager downloaded from GitHub"
        NORTHWIND_DOWNLOADED=true
    fi
fi

if [ "$NORTHWIND_DOWNLOADED" = true ]; then
    chown ga:ga /home/ga/manager-data/Northwind.manager
    echo "Northwind.manager ready at /home/ga/manager-data/Northwind.manager"
else
    echo ""
    echo "WARNING: Could not download Northwind.manager automatically."
    echo "Tasks will work with an empty Manager.io business."
    echo "To manually add Northwind: place Northwind.manager in /home/ga/manager-data/"
    # Create placeholder so container starts cleanly
    touch /home/ga/manager-data/.northwind_missing
fi

# Set up Firefox profile to suppress first-run dialogs
echo "Configuring Firefox profile..."
mkdir -p /home/ga/.mozilla/firefox/manager.profile
cat > /home/ga/.mozilla/firefox/manager.profile/user.js << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("browser.startup.homepage", "http://localhost:8080/");
user_pref("browser.startup.page", 1);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
USERJS

cat > /home/ga/.mozilla/firefox/profiles.ini << 'PROFILES'
[Install4F96D1932A9F858E]
Default=manager.profile
Locked=1

[Profile0]
Name=manager
IsRelative=1
Path=manager.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
PROFILES

chown -R ga:ga /home/ga/.mozilla

# Clean up apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Manager.io Installation Complete ==="
echo "Docker: $(docker --version)"
echo "Docker Compose: $(docker compose version)"
echo "Firefox: $(which firefox)"
echo "Northwind data: $(ls -lh /home/ga/manager-data/ 2>/dev/null || echo 'not found')"
