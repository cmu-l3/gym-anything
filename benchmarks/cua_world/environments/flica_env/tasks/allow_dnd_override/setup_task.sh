#!/system/bin/sh
echo "=== Setting up DND Override task ==="

# Create task directory
mkdir -p /sdcard/tasks/allow_dnd_override

# 1. Record task start time
date +%s > /sdcard/tasks/allow_dnd_override/start_time.txt

# 2. Reset DND state (Turn OFF)
echo "Resetting DND state..."
settings put global zen_mode 0
cmd notification set_dnd off 2>/dev/null || true

# 3. Attempt to clear specific app exception (best effort)
# This removes the app from the DND bypass list if it was there
cmd notification allow_dnd com.robert.fcView false 2>/dev/null || true

# 4. Record Initial State
INITIAL_ZEN=$(settings get global zen_mode)
# Check if app is currently in policy (should be clean now)
INITIAL_POLICY=$(dumpsys notification policy | grep "com.robert.fcView" || echo "none")

echo "Initial Zen Mode: $INITIAL_ZEN"
echo "Initial Policy: $INITIAL_POLICY"

# Save initial state to JSON
cat > /sdcard/tasks/allow_dnd_override/initial_state.json << EOF
{
  "zen_mode": "$INITIAL_ZEN",
  "policy_entry": "$INITIAL_POLICY",
  "timestamp": $(date +%s)
}
EOF

# 5. Launch App (ensure it's running)
echo "Launching Flight Crew View..."
monkey -p com.robert.fcView -c android.intent.category.LAUNCHER 1
sleep 5

# 6. Ensure we are logged in (using helper)
if [ -f /sdcard/scripts/login_helper.sh ]; then
    sh /sdcard/scripts/login_helper.sh
fi

# 7. Take initial screenshot
screencap -p /sdcard/tasks/allow_dnd_override/initial_state.png

echo "=== Setup complete ==="