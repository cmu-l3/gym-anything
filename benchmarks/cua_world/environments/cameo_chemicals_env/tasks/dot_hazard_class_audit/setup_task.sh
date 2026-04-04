#!/bin/bash
echo "=== Setting up DOT Hazard Class Audit Task ==="

# Source utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/manifest_audit_report.csv 2>/dev/null || true
rm -f /home/ga/Desktop/draft_manifest.csv 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 3. Create the Input Data (Draft Manifest)
# UN 1203 (Gasoline): Real=3, Listed=5.1 (FAIL)
# UN 1824 (NaOH): Real=8, Listed=8 (PASS)
# UN 1050 (HCl): Real=2.3, Listed=2.1 (FAIL)
# UN 2014 (H2O2): Real=5.1, Listed=3 (FAIL)
# UN 1090 (Acetone): Real=3, Listed=3 (PASS)

cat > /home/ga/Desktop/draft_manifest.csv << EOF
UN_Number,Chemical_Name,Listed_Hazard_Class
1203,Gasoline,5.1
1824,Sodium hydroxide solution,8
1050,Hydrogen chloride anhydrous,2.1
2014,Hydrogen peroxide aqueous,3
1090,Acetone,3
EOF

chown ga:ga /home/ga/Desktop/draft_manifest.csv
chmod 644 /home/ga/Desktop/draft_manifest.csv

echo "Created /home/ga/Desktop/draft_manifest.csv"

# 4. Launch Firefox to CAMEO Chemicals
if ! pgrep -f "firefox" > /dev/null; then
    echo "Launching Firefox..."
    su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO"; then
            echo "Firefox window detected."
            break
        fi
        sleep 1
    done
fi

# 5. Maximize and Focus
sleep 5
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# 6. Capture Initial Screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="