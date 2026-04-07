#!/bin/bash
echo "=== Setting up openvsp_cruise_to_landing_transition task ==="

# Source task utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Provide real base data (eCRM-001 from standard openvsp_env workspace data)
if [ -f "/workspace/data/eCRM-001_wing_tail.vsp3" ]; then
    cp "/workspace/data/eCRM-001_wing_tail.vsp3" "$MODELS_DIR/eCRM001_cruise.vsp3"
else
    # Fallback to copy from existing system models if workspace missing
    cp /opt/openvsp_models/*.vsp3 "$MODELS_DIR/eCRM001_cruise.vsp3" 2>/dev/null || true
fi
chmod 644 "$MODELS_DIR/eCRM001_cruise.vsp3"

# Write instructions to desktop
cat > /home/ga/Desktop/landing_config_checklist.txt << 'EOF'
=== HIGH-LIFT CONFIGURATION CHECKLIST ===
Model: eCRM-001

1. WING FLAPS
   - Select the main Wing component.
   - Go to the 'Sub' (Subsurface) tab.
   - Click 'Add' to create a new subsurface.
   - Set Type to 'Flap'.
   - Set Angle to 35.0 degrees.

2. TAIL INCIDENCE (TRIM)
   - Select the Horizontal Tail component.
   - Go to the 'XForm' tab.
   - Change the Pitch (Y rotation) to -3.0 degrees.

3. EXPORT
   - Save the model as: /home/ga/Documents/OpenVSP/eCRM001_landing.vsp3
EOF
chmod 644 /home/ga/Desktop/landing_config_checklist.txt
chown ga:ga /home/ga/Desktop/landing_config_checklist.txt

# Remove any previous task artifacts
rm -f "$MODELS_DIR/eCRM001_landing.vsp3"
rm -f /tmp/openvsp_landing_result.json

# Kill any running OpenVSP
kill_openvsp

# Launch OpenVSP with the cruise model
echo "Starting OpenVSP..."
launch_openvsp "$MODELS_DIR/eCRM001_cruise.vsp3"

# Wait for window, maximize, and focus
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    # Dismiss any update/startup dialogs
    dismiss_dialogs 2
    
    echo "Capturing initial state screenshot..."
    take_screenshot /tmp/task_initial.png
    
    # Verify screenshot was captured
    if [ -f /tmp/task_initial.png ]; then
        SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
        echo "Initial screenshot captured: ${SIZE} bytes"
    else
        echo "WARNING: Could not capture initial screenshot"
    fi
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually."
    take_screenshot /tmp/task_initial.png
fi

echo "=== Task setup complete ==="