#!/bin/bash
set -e
echo "=== Setting up implement_zone_recording_policy task ==="

source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Delete stale outputs BEFORE recording timestamp
# ---------------------------------------------------------------
rm -f /home/ga/Documents/schedule_audit.json
rm -f /tmp/task_result.json
rm -f /tmp/final_devices_state.json
rm -f /tmp/initial_devices_state.json

# ---------------------------------------------------------------
# 2. Record task start time
# ---------------------------------------------------------------
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 3. Ensure Nx Witness server is running and authenticate
# ---------------------------------------------------------------
echo "Checking VMS status..."
refresh_nx_token > /dev/null

# ---------------------------------------------------------------
# 4. Verify cameras are present
# ---------------------------------------------------------------
echo "Verifying camera availability..."
REQUIRED_CAMERAS=("Parking Lot Camera" "Entrance Camera" "Server Room Camera")
MISSING_CAMS=0

for cam_name in "${REQUIRED_CAMERAS[@]}"; do
    CAM_ID=$(get_camera_id_by_name "$cam_name")
    if [ -z "$CAM_ID" ]; then
        echo "WARNING: Camera '$cam_name' not found."
        MISSING_CAMS=$((MISSING_CAMS + 1))
    else
        echo "Found '$cam_name' ($CAM_ID)"
    fi
done

if [ "$MISSING_CAMS" -gt 1 ]; then
    echo "CRITICAL: Too many cameras missing. Attempting to restart testcamera..."
    pkill testcamera || true
    SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "127.0.0.1")
    TESTCAMERA=$(find /opt -name testcamera -type f | head -1)
    if [ -n "$TESTCAMERA" ]; then
        nohup "$TESTCAMERA" --local-interface="${SERVER_IP}" "channels=3" > /dev/null 2>&1 &
        sleep 15
    fi
fi

# ---------------------------------------------------------------
# 5. Reset all cameras to known "bad" state (misconfigurations)
#    Each camera gets a DIFFERENT wrong configuration.
# ---------------------------------------------------------------
echo "Applying misconfigurations..."

# Parking Lot Camera (Perimeter zone): DISABLE recording entirely
PARKING_ID=$(get_camera_id_by_name "Parking Lot Camera")
if [ -n "$PARKING_ID" ]; then
    nx_api_patch "/rest/v1/devices/${PARKING_ID}" '{"schedule": {"isEnabled": false, "tasks": []}}' > /dev/null
    echo "Parking Lot Camera: recording DISABLED"
fi

# Entrance Camera (Access Point zone): set to WRONG fps/quality (25fps high everywhere)
ENTRANCE_ID=$(get_camera_id_by_name "Entrance Camera")
if [ -n "$ENTRANCE_ID" ]; then
    WRONG_TASKS='['
    for d in 1 2 3 4 5 6 7; do
        [ "$d" -gt 1 ] && WRONG_TASKS="$WRONG_TASKS,"
        WRONG_TASKS="$WRONG_TASKS{\"dayOfWeek\":$d,\"startTime\":0,\"endTime\":86400,\"recordingType\":\"always\",\"fps\":25,\"streamQuality\":\"high\",\"bitrateKbps\":0,\"metadataTypes\":\"none\"}"
    done
    WRONG_TASKS="$WRONG_TASKS]"
    nx_api_patch "/rest/v1/devices/${ENTRANCE_ID}" "{
        \"schedule\": {\"isEnabled\": true, \"tasks\": $WRONG_TASKS}
    }" > /dev/null
    echo "Entrance Camera: set to always/25fps/high everywhere (wrong — needs split schedule)"
fi

# Server Room Camera (Restricted zone): DISABLE recording entirely
SERVER_ID=$(get_camera_id_by_name "Server Room Camera")
if [ -n "$SERVER_ID" ]; then
    nx_api_patch "/rest/v1/devices/${SERVER_ID}" '{"schedule": {"isEnabled": false, "tasks": []}}' > /dev/null
    echo "Server Room Camera: recording DISABLED"
fi

# Set retention to 7 days on all cameras (wrong for all zones)
# NOTE: Retention requires v2 API - v1 rejects schedule-only patches with retention fields
TOKEN=$(get_nx_token)
for CAM_ID in "$PARKING_ID" "$ENTRANCE_ID" "$SERVER_ID"; do
    if [ -n "$CAM_ID" ]; then
        curl -sk -X PATCH "https://localhost:7001/rest/v2/devices/${CAM_ID}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d '{"schedule": {"minArchiveDays": 7, "maxArchiveDays": 7, "minArchivePeriodS": 604800, "maxArchivePeriodS": 604800}}' > /dev/null 2>&1 || true
    fi
done
echo "All cameras: retention set to 7 days (wrong for all zones)"

# ---------------------------------------------------------------
# 6. Record initial device state for anti-gaming verification
# ---------------------------------------------------------------
nx_api_get "/rest/v1/devices" > /tmp/initial_devices_state.json

# ---------------------------------------------------------------
# 7. Create the policy document at /home/ga/Documents/
# ---------------------------------------------------------------
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/recording_policy.json << 'POLICY_EOF'
{
  "policy_name": "Zone-Based Recording Standard - Rev 3.1",
  "effective_date": "2026-03-01",
  "facility": "Warehouse Distribution Center - Site 07",
  "business_hours": {
    "days": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"],
    "start": "07:00",
    "end": "19:00"
  },
  "zones": {
    "Perimeter": {
      "description": "Exterior areas requiring constant surveillance regardless of time",
      "cameras": ["Parking Lot Camera"],
      "recording": {
        "business_hours": {
          "mode": "continuous",
          "frame_rate": 15,
          "quality": "high"
        },
        "off_hours": {
          "mode": "continuous",
          "frame_rate": 10,
          "quality": "normal"
        }
      },
      "retention": {
        "minimum_days": 90,
        "maximum_days": 180
      }
    },
    "Access Point": {
      "description": "Controlled entry/exit points with high daytime traffic",
      "cameras": ["Entrance Camera"],
      "recording": {
        "business_hours": {
          "mode": "continuous",
          "frame_rate": 15,
          "quality": "high"
        },
        "off_hours": {
          "mode": "continuous",
          "frame_rate": 5,
          "quality": "low"
        }
      },
      "retention": {
        "minimum_days": 60,
        "maximum_days": 120
      }
    },
    "Restricted": {
      "description": "Sensitive areas requiring heightened after-hours monitoring",
      "cameras": ["Server Room Camera"],
      "recording": {
        "business_hours": {
          "mode": "continuous",
          "frame_rate": 10,
          "quality": "normal"
        },
        "off_hours": {
          "mode": "continuous",
          "frame_rate": 15,
          "quality": "high"
        }
      },
      "retention": {
        "minimum_days": 180,
        "maximum_days": 365
      }
    }
  }
}
POLICY_EOF
chown ga:ga /home/ga/Documents/recording_policy.json

# ---------------------------------------------------------------
# 8. Ensure Firefox SSL exception is accepted and Web Admin is logged in
#    The NX Witness self-signed cert has SAN=<server-uuid>, not localhost,
#    so Firefox always shows SSL warning. We must dismiss it for the agent.
# ---------------------------------------------------------------
echo "Setting up Firefox with NX Witness Web Admin..."

# Install certutil if not present (for cert import)
which certutil > /dev/null 2>&1 || apt-get install -y libnss3-tools > /dev/null 2>&1 || true

# Import the NX Witness server cert into Firefox's NSS database
FF_PROFILE=$(find /home/ga/snap/firefox/common/.mozilla/firefox -name "*.default*" -maxdepth 1 -type d 2>/dev/null | head -1)
if [ -z "$FF_PROFILE" ]; then
    FF_PROFILE=$(find /home/ga/.mozilla/firefox -name "*.default*" -maxdepth 1 -type d 2>/dev/null | head -1)
fi

if [ -n "$FF_PROFILE" ]; then
    echo "Firefox profile: $FF_PROFILE"
    # Extract server cert
    echo | openssl s_client -connect localhost:7001 2>/dev/null | openssl x509 > /tmp/nx_cert.pem 2>/dev/null || true
    if [ -s /tmp/nx_cert.pem ]; then
        # Kill Firefox so we can modify its cert database safely
        pkill -f firefox 2>/dev/null || true
        sleep 3
        certutil -A -n "NxWitness" -t "TCu,Cu,Tu" -i /tmp/nx_cert.pem -d "sql:${FF_PROFILE}" 2>/dev/null || true
        echo "Certificate imported into Firefox NSS database"
    fi
fi

# Launch Firefox to the NX Witness Web Admin
su - ga -c "DISPLAY=:1 firefox 'https://localhost:7001/static/index.html' &" 2>/dev/null || true
sleep 12

# If SSL warning still appears (cert hostname mismatch), dismiss it via keyboard
# Shift+Tab focuses the "Accept the Risk and Continue" button, then Enter clicks it
DISPLAY=:1 xdotool key shift+Tab Return 2>/dev/null || true
sleep 8

# Now log in: click Login field, type credentials
# Login field coordinates at center of the form
DISPLAY=:1 xdotool mousemove 960 555 click 1 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a 2>/dev/null || true
DISPLAY=:1 xdotool type "admin" 2>/dev/null || true
sleep 0.3
DISPLAY=:1 xdotool key Tab 2>/dev/null || true
sleep 0.3
DISPLAY=:1 xdotool type "${NX_ADMIN_PASS}" 2>/dev/null || true
sleep 0.3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.3
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 10

# Dismiss "Save password?" Firefox dialog
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# ---------------------------------------------------------------
# 9. Open a terminal for the agent
# ---------------------------------------------------------------
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
fi
sleep 2

# ---------------------------------------------------------------
# 10. Take initial screenshot
# ---------------------------------------------------------------
take_screenshot /tmp/implement_zone_recording_policy_start.png

echo "=== Task setup complete ==="
echo "State: All 3 cameras misconfigured with wrong schedules and 7-day retention"
echo "State: Policy document placed at /home/ga/Documents/recording_policy.json"
echo "State: Firefox logged into NX Witness Web Admin"
echo "Task: Agent must read policy, configure zone-based schedules and retention via API, generate report"
