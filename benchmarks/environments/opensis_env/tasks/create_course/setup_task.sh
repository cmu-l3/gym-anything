#!/bin/bash
set -euo pipefail

echo "=== Setting up create_course task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Ensure services are running
systemctl is-active --quiet mariadb || systemctl start mariadb
systemctl is-active --quiet apache2 || systemctl start apache2
sleep 2

# Kill any existing Chrome instances for clean start
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true
sleep 1

# Start Chrome with OpenSIS
echo "Starting Chrome with OpenSIS..."

if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

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

# Wait for window and focus
for i in {1..30}; do
    if wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        break
    fi
    sleep 1
done

wmctrl -a "Chrome" 2>/dev/null || wmctrl -a "Chromium" 2>/dev/null || true
wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "=== Task setup complete ==="
echo ""
echo "Task: Create a new course with the following information:"
echo "  - Course name: Advanced Chemistry"
echo "  - Course code: CHEM201"
echo "  - Subject area: Science"
echo "  - Grade level: 11"
echo "  - Credits: 1.0"
