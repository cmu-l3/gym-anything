#!/bin/bash
# set -euo pipefail

echo "=== Setting up Screaming Frog SEO Spider configuration ==="

# Set up for a specific user
setup_user_screamingfrog() {
    local username=$1
    local home_dir=$2

    echo "Setting up Screaming Frog for user: $username"

    # Create necessary directories
    sudo -u $username mkdir -p "$home_dir/.ScreamingFrogSEOSpider"
    sudo -u $username mkdir -p "$home_dir/Documents/SEO"
    sudo -u $username mkdir -p "$home_dir/Documents/SEO/crawls"
    sudo -u $username mkdir -p "$home_dir/Documents/SEO/exports"
    sudo -u $username mkdir -p "$home_dir/Documents/SEO/reports"
    sudo -u $username mkdir -p "$home_dir/Documents/SEO/sitemaps"
    sudo -u $username mkdir -p "$home_dir/Desktop"

    # Create default configuration to disable first-run dialogs
    # The config file is spider.config
    cat > "$home_dir/.ScreamingFrogSEOSpider/spider.config" << 'CONFIGEOF'
# Screaming Frog SEO Spider Configuration
# Disable update checks and telemetry
checkForUpdates=false
sendCrashReports=false
sendUsageStats=false

# Set default export directory
exportDirectory=/home/ga/Documents/SEO/exports

# Database storage mode (better for larger crawls)
storageMode=database

# Memory settings
maxUriQueue=5000000
memoryLimit=4096

# Crawl settings
respectRobotsTxt=true
followRedirects=true
crawlCanonicals=true
CONFIGEOF

    # Replace home dir placeholder
    sed -i "s|/home/ga|$home_dir|g" "$home_dir/.ScreamingFrogSEOSpider/spider.config"
    chown -R $username:$username "$home_dir/.ScreamingFrogSEOSpider"
    echo "  - Created default spider.config"

    # Create desktop shortcut
    cat > "$home_dir/Desktop/ScreamingFrog.desktop" << 'DESKTOPEOF'
[Desktop Entry]
Name=Screaming Frog SEO Spider
Comment=Website Crawler for SEO Audits
Exec=/opt/ScreamingFrogSEOSpider/ScreamingFrogSEOSpider
Icon=/opt/ScreamingFrogSEOSpider/ScreamingFrogSEOSpider.png
StartupNotify=true
Terminal=false
Type=Application
Categories=Network;WebDevelopment;
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/ScreamingFrog.desktop"
    chmod +x "$home_dir/Desktop/ScreamingFrog.desktop"
    echo "  - Created desktop shortcut"

    # Create launch script
    cat > "$home_dir/launch_screamingfrog.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch Screaming Frog SEO Spider with optimized settings
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Set Java options for better memory management
export _JAVA_OPTIONS="-Xms512m -Xmx4096m"

# Launch Screaming Frog
if command -v screamingfrogseospider &> /dev/null; then
    screamingfrogseospider "$@" > /tmp/screamingfrog_$USER.log 2>&1 &
elif [ -x "/opt/ScreamingFrogSEOSpider/ScreamingFrogSEOSpider" ]; then
    /opt/ScreamingFrogSEOSpider/ScreamingFrogSEOSpider "$@" > /tmp/screamingfrog_$USER.log 2>&1 &
else
    echo "ERROR: Screaming Frog SEO Spider not found"
    exit 1
fi

echo "Screaming Frog started"
echo "Log file: /tmp/screamingfrog_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_screamingfrog.sh"
    chmod +x "$home_dir/launch_screamingfrog.sh"
    echo "  - Created launch script"

    # Set proper permissions
    chown -R $username:$username "$home_dir/Documents/SEO"
    chmod -R 755 "$home_dir/Documents/SEO"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_screamingfrog "ga" "/home/ga"
fi

# NOTE: This environment uses REAL public websites for testing
# - Primary test URL: https://crawler-test.com/
# - Broken links test: https://crawler-test.com/links/broken_links
# NO local test website is created - agents must use real websites

echo "=== Screaming Frog SEO Spider configuration completed ==="
echo "Screaming Frog is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run '~/launch_screamingfrog.sh' from terminal"
echo ""
echo "IMPORTANT: Use REAL websites for crawling:"
echo "  - https://crawler-test.com/ (primary test URL)"
echo "  - https://crawler-test.com/links/broken_links (broken links test)"
echo "  - Crawl reports saved to ~/Documents/SEO/exports"
