#!/bin/bash
# Manager.io Setup Script (post_start hook)
# Starts Manager.io Server via Docker and opens Firefox at the login page.
#
# Manager.io Server Edition:
#   URL:      http://localhost:8080/
#   Username: administrator
#   Password: (empty — leave blank and click Sign In)
#
# Sample data: Northwind Traders — a fictitious food trading company with
# realistic customers, suppliers, inventory items, invoices, and receipts.

set -e

echo "=== Setting up Manager.io ==="

MANAGER_URL="http://localhost:8080"

# ---------------------------------------------------------------------------
# Helper: wait for Manager.io HTTP service to be ready
# ---------------------------------------------------------------------------
wait_for_manager() {
    local timeout=${1:-120}
    local elapsed=0

    echo "Waiting for Manager.io to be ready..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -L "$MANAGER_URL/" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
            echo "Manager.io is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done

    echo "WARNING: Manager.io readiness check timed out after ${timeout}s"
    return 1
}

# ---------------------------------------------------------------------------
# Step 1: Set up Docker Compose configuration
# ---------------------------------------------------------------------------
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/manager
cp /workspace/config/docker-compose.yml /home/ga/manager/
chown -R ga:ga /home/ga/manager

# ---------------------------------------------------------------------------
# Step 2: Pull Docker image and start Manager.io container
# ---------------------------------------------------------------------------
echo "Pulling Manager.io Docker image..."
cd /home/ga/manager
docker compose pull 2>&1 | tail -5

echo "Starting Manager.io container..."
docker compose up -d
echo "Container started."
docker compose ps

# ---------------------------------------------------------------------------
# Step 3: Wait for Manager.io to be accessible
# ---------------------------------------------------------------------------
wait_for_manager 120

# ---------------------------------------------------------------------------
# Step 4: Create business and seed data via API
# ---------------------------------------------------------------------------
echo "Setting up Northwind Traders business and seed data..."
bash /workspace/scripts/setup_data.sh 2>&1 || echo "WARNING: Seed data setup had errors (non-fatal)"

# ---------------------------------------------------------------------------
# Step 5: Configure Firefox profile and set up desktop
# ---------------------------------------------------------------------------
echo "Configuring Firefox..."

# Ensure Firefox profile directory exists with correct permissions
mkdir -p /home/ga/.mozilla/firefox/manager.profile
chown -R ga:ga /home/ga/.mozilla

# Create a desktop shortcut for easy access
cat > /home/ga/Desktop/Manager.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Manager.io Accounting
Comment=Open Manager.io accounting software
Exec=firefox --new-window http://localhost:8080/
Icon=accessories-calculator
Terminal=false
Categories=Office;Finance;
EOF
chmod +x /home/ga/Desktop/Manager.desktop
chown ga:ga /home/ga/Desktop/Manager.desktop

# ---------------------------------------------------------------------------
# Step 6: Open Firefox at Manager.io login page
# ---------------------------------------------------------------------------
echo "Opening Firefox at Manager.io..."

# Ensure DISPLAY is available
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Small wait for desktop to settle
sleep 3

# Start Firefox with the Manager.io profile
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid firefox \
    -profile /home/ga/.mozilla/firefox/manager.profile \
    --new-window 'http://localhost:8080/' \
    > /tmp/firefox_manager.log 2>&1 &"

# Wait for Firefox to launch
sleep 10

# Maximize Firefox window
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any first-run dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

echo ""
echo "=== Manager.io Setup Complete ==="
echo ""
echo "Manager.io is running at: http://localhost:8080/"
echo "Default login:"
echo "  Username: administrator"
echo "  Password: (empty — just click Sign In)"
echo ""
echo "Business: Northwind Traders (with customers, suppliers, bank account)"
echo ""
echo "Firefox has been opened at the Manager.io login page."
