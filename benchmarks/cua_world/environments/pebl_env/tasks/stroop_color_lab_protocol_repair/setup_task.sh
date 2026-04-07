#!/bin/bash
# Setup for stroop_color_lab_protocol_repair task
# Creates a lab protocol JSON with 5 intentional errors
# Correct values: practice_trials=12, test_trials_per_block=48, blocks=4, isi_ms=500,
#                 response_colors=["red","blue","green","yellow"]
# Injected wrong values in ALL 5 fields

set -e
echo "=== Setting up stroop_color_lab_protocol_repair task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/lab
chown -R ga:ga /home/ga/pebl

# Create the corrupted protocol file (all 5 parameters wrong)
cat > /home/ga/pebl/lab/stroop_protocol.json << 'JSONEOF'
{
  "experiment": "Color-Naming Stroop Task",
  "version": "2.1",
  "reference": "Steinhauser & Huebner (2009) replication",
  "last_modified": "2024-11-15",
  "lab_code": "CogPsychLab-A",
  "parameters": {
    "practice_trials": 20,
    "test_trials_per_block": 36,
    "blocks": 6,
    "isi_ms": 750,
    "response_colors": ["red", "blue", "green", "purple"]
  },
  "stimuli": {
    "font_size_pt": 36,
    "display_duration_ms": 500,
    "mask_duration_ms": 100
  },
  "response_keys": {
    "red": "f",
    "blue": "g",
    "green": "h",
    "yellow": "j"
  },
  "output_dir": "~/pebl/data/stroop",
  "notes": "Multi-site replication protocol. Any parameter changes must be approved by the PI and communicated to all partner sites before the next data collection wave."
}
JSONEOF

chown ga:ga /home/ga/pebl/lab/stroop_protocol.json
chmod 644 /home/ga/pebl/lab/stroop_protocol.json

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open the file in gedit for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gedit /home/ga/pebl/lab/stroop_protocol.json > /tmp/gedit_stroop.log 2>&1 &"

for i in $(seq 1 20); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "stroop_protocol" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        echo "gedit window found: $WID"
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== stroop_color_lab_protocol_repair setup complete ==="
echo "Protocol file: /home/ga/pebl/lab/stroop_protocol.json"
echo "All 5 parameters are wrong and must be corrected to match the canonical protocol"
