#!/bin/bash
set -e

echo "=== Setting up Moderate Dismiss Raised Hand task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Kill any existing firefox
stop_firefox

# ── Create Two Distinct Profiles (Alice and Bob) ─────────────────────────────
# This ensures they don't share local storage/session state (acting as distinct users)
PROFILE_BASE="/home/ga/.mozilla/firefox"
ALICE_DIR="$PROFILE_BASE/alice.profile"
BOB_DIR="$PROFILE_BASE/bob.profile"

mkdir -p "$ALICE_DIR" "$BOB_DIR"

# Copy the environment's default hardened prefs to both
if [ -f "$PROFILE_BASE/jitsi.profile/user.js" ]; then
    cp "$PROFILE_BASE/jitsi.profile/user.js" "$ALICE_DIR/"
    cp "$PROFILE_BASE/jitsi.profile/user.js" "$BOB_DIR/"
fi

# Update profiles.ini to recognize them
cat > "$PROFILE_BASE/profiles.ini" << EOF
[Profile0]
Name=alice
IsRelative=1
Path=alice.profile
Default=1

[Profile1]
Name=bob
IsRelative=1
Path=bob.profile
Default=0

[General]
StartWithLastProfile=0
Version=2
EOF

# ── Launch Two Windows ───────────────────────────────────────────────────────
MEETING_URL="http://localhost:8080/TownHallQandA"

echo "Launching Moderator Alice (Left Window)..."
# Using --no-remote to allow multiple instances
DISPLAY=:1 nohup firefox -P alice --no-remote --class "FirefoxAlice" "$MEETING_URL" >/dev/null 2>&1 &
ALICE_PID=$!
sleep 5

echo "Launching Guest Bob (Right Window)..."
DISPLAY=:1 nohup firefox -P bob --no-remote --class "FirefoxBob" "$MEETING_URL" >/dev/null 2>&1 &
BOB_PID=$!
sleep 8

# ── Arrange Windows Side-by-Side ─────────────────────────────────────────────
# We use xdotool search to find windows. Since we set --class, we might be able to target them,
# but Firefox snap/binary might override class. We'll use window title or sequence.

echo "Arranging windows..."

# Get all Firefox window IDs
WIN_IDS=$(DISPLAY=:1 xdotool search --class "firefox")

# We expect at least 2 IDs. We'll arbitrarily assign the first found to Left, second to Right.
# (If they are the same window, something failed, but we assume success).
ID_1=$(echo "$WIN_IDS" | head -n1)
ID_2=$(echo "$WIN_IDS" | tail -n1)

if [ -z "$ID_1" ] || [ -z "$ID_2" ] || [ "$ID_1" == "$ID_2" ]; then
    echo "WARNING: Could not identify two distinct windows. Trying generic arrangement."
fi

# Position Left Window (Alice)
DISPLAY=:1 wmctrl -i -r "$ID_1" -e 0,0,0,960,1080
DISPLAY=:1 xdotool windowactivate "$ID_1"
# Set title if possible or just rely on position for the agent description

# Position Right Window (Bob)
DISPLAY=:1 wmctrl -i -r "$ID_2" -e 0,960,0,960,1080

# Bring both to front
DISPLAY=:1 wmctrl -i -a "$ID_1"
DISPLAY=:1 wmctrl -i -a "$ID_2"

# Ensure no blocking dialogs (hit Escape on both)
DISPLAY=:1 xdotool windowfocus "$ID_1" key Escape
sleep 0.5
DISPLAY=:1 xdotool windowfocus "$ID_2" key Escape

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Left Window (Alice): $ID_1"
echo "Right Window (Bob): $ID_2"