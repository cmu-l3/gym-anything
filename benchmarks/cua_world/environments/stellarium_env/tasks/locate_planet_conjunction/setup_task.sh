#!/bin/bash
echo "=== Setting up locate_planet_conjunction task ==="

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

# ── 5. Create a distinctly different start state:
#    Turn off atmosphere and ground, enable constellation lines.
#    This produces a dark starfield with constellation patterns —
#    very different from the other task start states.
focus_stellarium
sleep 0.5
DISPLAY=:1 xdotool key a 2>/dev/null || true   # atmosphere OFF
sleep 0.5
DISPLAY=:1 xdotool key g 2>/dev/null || true   # ground OFF
sleep 0.5
DISPLAY=:1 xdotool key c 2>/dev/null || true   # constellation lines ON
sleep 0.5
DISPLAY=:1 xdotool key v 2>/dev/null || true   # constellation names ON
sleep 1

# ── 6. Record initial state for verification ─────────────────────────
cp /home/ga/.stellarium/config.ini /tmp/initial_stellarium_config.ini 2>/dev/null || true

# ── 7. Take initial screenshot ───────────────────────────────────────
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should see a dark starfield with constellation lines and names, no atmosphere or ground."
echo "Task: Set date to Dec 21 2020, location to Paranal, find Jupiter-Saturn conjunction, zoom in."
