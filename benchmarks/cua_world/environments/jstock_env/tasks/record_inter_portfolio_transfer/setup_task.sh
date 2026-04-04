#!/bin/bash
set -e
echo "=== Setting up record_inter_portfolio_transfer task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# ============================================================
# Prepare JStock Data Directories
# We need two portfolios: "Safe Harbor" and "Growth Fund"
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIOS_DIR="${JSTOCK_DATA_DIR}/portfolios"

# Ensure base directories exist
mkdir -p "$PORTFOLIOS_DIR"

# ------------------------------------------------------------
# 1. Setup "Safe Harbor" Portfolio (Source)
# Needs initial capital so withdrawal makes sense
# ------------------------------------------------------------
SAFE_DIR="${PORTFOLIOS_DIR}/Safe Harbor"
mkdir -p "$SAFE_DIR"

# Standard empty portfolio files
cat > "${SAFE_DIR}/buyportfolio.csv" << 'EOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
EOF

cat > "${SAFE_DIR}/sellportfolio.csv" << 'EOF'
"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
EOF

# Seed with initial deposit
cat > "${SAFE_DIR}/depositsummary.csv" << 'EOF'
"Date","Amount","Comment"
"Jan 01, 2024","50000.0","Initial Capital"
EOF

# Empty withdrawal file (Agent will write here)
cat > "${SAFE_DIR}/withdrawalsummary.csv" << 'EOF'
"Date","Amount","Comment"
EOF

cat > "${SAFE_DIR}/dividendsummary.csv" << 'EOF'
"Code","Symbol","Date","Amount","Comment"
EOF

# ------------------------------------------------------------
# 2. Setup "Growth Fund" Portfolio (Destination)
# Initially empty
# ------------------------------------------------------------
GROWTH_DIR="${PORTFOLIOS_DIR}/Growth Fund"
mkdir -p "$GROWTH_DIR"

cat > "${GROWTH_DIR}/buyportfolio.csv" << 'EOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
EOF

cat > "${GROWTH_DIR}/sellportfolio.csv" << 'EOF'
"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
EOF

# Empty deposit file (Agent will write here)
cat > "${GROWTH_DIR}/depositsummary.csv" << 'EOF'
"Date","Amount","Comment"
EOF

cat > "${GROWTH_DIR}/withdrawalsummary.csv" << 'EOF'
"Date","Amount","Comment"
EOF

cat > "${GROWTH_DIR}/dividendsummary.csv" << 'EOF'
"Code","Symbol","Date","Amount","Comment"
EOF

# ------------------------------------------------------------
# 3. Setup Default/Dummy "My Portfolio" (Optional but good for realism)
# ------------------------------------------------------------
DEFAULT_DIR="${PORTFOLIOS_DIR}/My Portfolio"
mkdir -p "$DEFAULT_DIR"
# Just ensure it exists so JStock doesn't complain, can be empty
touch "${DEFAULT_DIR}/buyportfolio.csv"

# ============================================================
# Permissions and Launch
# ============================================================
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

echo "Portfolios prepared: Safe Harbor (Seeded) & Growth Fund (Empty)"

# Launch JStock
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

echo "Waiting for JStock to start (30 seconds)..."
sleep 30

# Dismiss JStock News dialog
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# Maximize window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Navigate to Portfolio Management tab (approx coords for 1920x1080)
# This helps the agent start in the right context
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 735 158 click 1" 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png" 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="