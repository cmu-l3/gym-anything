#!/bin/bash
echo "=== Setting up observe_solar_eclipse task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Ensure Stellarium is running ──────────────────────────────────
ensure_stellarium_running
sleep 5

# ── 2. Dismiss any dialogs ───────────────────────────────────────────
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# ── 3. Maximize and focus Stellarium ─────────────────────────────────
maximize_stellarium
focus_stellarium
sleep 2

# ── 4. Reset to default view ─────────────────────────────────────────
reset_view
sleep 1

# ── 5. Set time to noon to create a bright DAYTIME sky start state.
#    This is visually very different from the other tasks (nighttime).
#    Open the Date/Time dialog (F5), click on the hour field, type 12.
#    F5 dialog coordinates (1280x720 scale, scaled to 1920x1080):
#      Hour field:   (698, 402) -> (1047, 603)
#      Minute field: (758, 402) -> (1137, 603)
#      Second field: (822, 402) -> (1233, 603)
focus_stellarium
sleep 0.5
DISPLAY=:1 xdotool key F5 2>/dev/null || true
sleep 2

# Click hour field, select all, type 12
DISPLAY=:1 xdotool mousemove 1047 603 click 1 click 1 click 1 2>/dev/null || true
sleep 0.3
DISPLAY=:1 xdotool key ctrl+a 2>/dev/null || true
sleep 0.2
DISPLAY=:1 xdotool type --clearmodifiers "12" 2>/dev/null || true
sleep 0.3

# Click minute field, select all, type 00
DISPLAY=:1 xdotool mousemove 1137 603 click 1 click 1 click 1 2>/dev/null || true
sleep 0.3
DISPLAY=:1 xdotool key ctrl+a 2>/dev/null || true
sleep 0.2
DISPLAY=:1 xdotool type --clearmodifiers "00" 2>/dev/null || true
sleep 0.3

# Click second field, select all, type 00
DISPLAY=:1 xdotool mousemove 1233 603 click 1 click 1 click 1 2>/dev/null || true
sleep 0.3
DISPLAY=:1 xdotool key ctrl+a 2>/dev/null || true
sleep 0.2
DISPLAY=:1 xdotool type --clearmodifiers "00" 2>/dev/null || true
sleep 0.5

# Close dialog
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# ── 6. Copy eclipse reference data for the agent ─────────────────────
cp /workspace/data/historical_eclipses.json /home/ga/data/ 2>/dev/null || true
chown -R ga:ga /home/ga/data 2>/dev/null || true

# ── 7. Record initial state for verification ─────────────────────────
cp /home/ga/.stellarium/config.ini /tmp/initial_stellarium_config.ini 2>/dev/null || true

# ── 8. Take initial screenshot ───────────────────────────────────────
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should see a bright daytime sky (noon) from the default location."
echo "Task: Navigate to Hopkinsville KY, Aug 21 2017 ~18:24 UTC to observe eclipse totality."
