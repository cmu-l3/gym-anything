#!/bin/bash
set -euo pipefail

echo "=== Setting up configure_custom_notification_sound task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# 1. Create the audio file that the agent needs to upload
echo "Generating target audio file..."
python3 -c "
import wave, struct, math
with wave.open('/home/ga/release_ping.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(44100)
    for i in range(22050):  # 0.5 seconds
        v = int(32767.0 * math.cos(880.0 * math.pi * float(i) / 44100.0) * (1.0 - i/22050.0))
        f.writeframesraw(struct.pack('<h', v))
"
chown ga:ga /home/ga/release_ping.wav

# Verify Rocket.Chat API is reachable
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
fi

# Verify login credentials work
for _ in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

if ! api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
  echo "ERROR: Task login credentials are not valid yet"
  exit 1
fi

# 2. Enforce clean initial state via MongoDB directly 
# Delete any pre-existing "release_ping" custom sound
echo "Ensuring clean workspace state..."
docker exec rc-mongodb mongosh --quiet "mongodb://localhost:27017/rocketchat?directConnection=true" --eval 'db.rocketchat_custom_sounds.deleteMany({name: "release_ping"})' || true

# Reset notification preferences for the #release-updates channel
docker exec rc-mongodb mongosh --quiet "mongodb://localhost:27017/rocketchat?directConnection=true" --eval 'db.rocketchat_subscription.updateOne({ "u.username": "admin", name: "release-updates" }, { $unset: { audioNotificationValue: "" } })' || true

# Copy seed manifest for reference
if [ ! -f "$SEED_MANIFEST_FILE" ] && [ -f "/home/ga/rocket_chat_seed_manifest.json" ]; then
  cp "/home/ga/rocket_chat_seed_manifest.json" "$SEED_MANIFEST_FILE"
fi

# Start Firefox at Rocket.Chat login page
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  DISPLAY=:1 wmctrl -l 2>/dev/null || true
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="