#!/bin/bash
set -euo pipefail

echo "=== Setting up add_student task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Ensure services are running
echo "Checking services..."
systemctl is-active --quiet mariadb || systemctl start mariadb
systemctl is-active --quiet apache2 || systemctl start apache2

# Wait for services
sleep 2

# Verify OpenSIS is accessible
if ! curl -s http://localhost/opensis/ >/dev/null 2>&1; then
    echo "WARNING: OpenSIS may not be accessible"
fi

# Check if OpenSIS was installed properly via installer
# The installer creates admin with password Admin@123
echo "Verifying OpenSIS installation..."
if mysql -u root opensis -e "SELECT 1 FROM login_authentication WHERE username='admin'" 2>/dev/null | grep -q "1"; then
    echo "OpenSIS admin user found"
else
    echo "WARNING: Admin user not found - installation may be incomplete"
fi

# Kill any existing Chrome instances for clean start
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true
sleep 1

# Start Chrome with OpenSIS login page
echo "Starting Chrome with OpenSIS..."

# Detect browser
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
elif command -v chrome-browser &> /dev/null; then
    CHROME_CMD="chrome-browser"
else
    echo "ERROR: No Chrome/Chromium browser found!"
    exit 1
fi

# Launch Chrome as ga user
nohup sudo -u ga $CHROME_CMD \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --window-size=1920,1080 \
    --disable-infobars \
    --password-store=basic \
    "http://localhost/opensis/" > /home/ga/chrome_opensis.log 2>&1 &

sleep 5

# Wait for window to appear
for i in {1..30}; do
    if wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        echo "Browser window detected"
        break
    fi
    sleep 1
done

# Focus the browser window
wmctrl -a "Chrome" 2>/dev/null || wmctrl -a "Chromium" 2>/dev/null || true

# Make window fullscreen
wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "=== Task setup complete ==="
echo ""
echo "Login credentials (from installer):"
echo "  - Username: admin"
echo "  - Password: Admin@123"
echo ""
echo "Task: Add a new student with the following information:"
echo "  - First name: Emily"
echo "  - Last name: Johnson"
echo "  - Date of birth: 2008-03-15"
echo "  - Gender: Female"
echo "  - Grade level: 10"
echo ""
echo "Navigate to Students > Add Student and fill in the form."
