#!/bin/bash
echo "=== Setting up configure_deep_sky_observation task ==="

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

# ── 4. Reset to default view with default settings ───────────────────
# Keep the default nighttime view: atmosphere ON, ground visible,
# no overlays. The agent must reconfigure everything from scratch.
reset_view
sleep 1

# ── 5. Copy real observatory and Messier data to accessible location ──
cp /workspace/data/observatory_locations.json /home/ga/data/ 2>/dev/null || true
cp /workspace/data/messier_catalog.json /home/ga/data/ 2>/dev/null || true
chown -R ga:ga /home/ga/data 2>/dev/null || true

# ── 6. Record initial state for verification ─────────────────────────
cp /home/ga/.stellarium/config.ini /tmp/initial_stellarium_config.ini 2>/dev/null || true

# ── 7. Take initial screenshot ───────────────────────────────────────
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should see Stellarium's default nighttime view with atmosphere and ground."
echo "Task: Set location to Mauna Kea, date to Jan 15 2025 06:00 UTC,"
echo "      configure for professional deep-sky observation, find and zoom into M31."
