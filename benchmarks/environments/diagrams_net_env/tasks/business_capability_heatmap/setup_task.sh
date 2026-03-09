#!/bin/bash
set -e

echo "=== Setting up Business Capability Heatmap Task ==="

# 1. Prepare Directories
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Diagrams /home/ga/Desktop

# 2. Create the Data CSV
CSV_FILE="/home/ga/Desktop/retail_capabilities.csv"
cat > "$CSV_FILE" << 'EOF'
Domain,Capability,Status,Description
Supply Chain,Procurement,Healthy,Sourcing and purchasing raw materials
Supply Chain,Inventory Management,Critical,Real-time stock tracking and optimization
Supply Chain,Logistics & Fulfillment,At Risk,Last-mile delivery and warehousing
Sales & Marketing,Campaign Management,Healthy,Multi-channel ad orchestration
Sales & Marketing,Customer 360,Critical,Unified customer data platform
Sales & Marketing,E-Commerce Storefront,Healthy,Web and mobile shopping experience
HR & Support,Talent Acquisition,At Risk,Recruiting and onboarding pipelines
HR & Support,Payroll & Benefits,Healthy,Compensation management
Finance,Financial Planning,At Risk,Budgeting and forecasting
Finance,General Ledger,Healthy,Core accounting and reporting
EOF
chown ga:ga "$CSV_FILE"
chmod 644 "$CSV_FILE"

# 3. Clean previous artifacts
rm -f /home/ga/Diagrams/capability_map.drawio
rm -f /home/ga/Diagrams/capability_map.pdf
rm -f /tmp/task_result.json

# 4. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch draw.io
# Kill existing instances first
pkill -f drawio 2>/dev/null || true
sleep 1

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /dev/null 2>&1 &"

# 6. Wait for Window & Handle Updates
# This loop aggressively checks for and dismisses the update dialog
echo "Waiting for draw.io and handling update dialogs..."
for i in $(seq 1 30); do
    # Check for update dialog
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "update|confirm"; then
        echo "Dismissing update dialog..."
        DISPLAY=:1 xdotool key Escape
        sleep 0.5
    fi
    
    # Check if main window is up
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "Main window detected."
        break
    fi
    sleep 1
done

# Additional safety dismissals
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Maximize Window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="