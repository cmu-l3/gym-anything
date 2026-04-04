#!/bin/bash
# Do NOT use set -e: some commands may fail non-fatally

echo "=== Setting up System Advisor Model (SAM) ==="

# Wait for desktop to be ready
sleep 5

# Kill any SAM GUI that auto-launched during boot (we'll relaunch cleanly)
killall -9 sam sam.bin SAM 2>/dev/null || true
sleep 1

# Create SAM config directory
mkdir -p /home/ga/.SAM
chown -R ga:ga /home/ga/.SAM

# Create desktop directory
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Desktop

# Create Documents directory for SAM projects
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents

# Locate SAM directory
SAM_DIR=""
if [ -f "/opt/SAM/sam_dir.txt" ]; then
    SAM_DIR=$(cat /opt/SAM/sam_dir.txt)
fi

# Find weather data bundled with SAM and record the path
SOLAR_RES=""
if [ -n "$SAM_DIR" ]; then
    SOLAR_RES=$(find "$SAM_DIR" -type d -name "solar_resource" 2>/dev/null | head -1)

    if [ -n "$SOLAR_RES" ]; then
        echo "$SOLAR_RES" > /home/ga/.SAM/solar_resource_dir.txt
    fi
fi

# Verify PySAM is available (silent check, no output to agent)
python3 -c "import PySAM.Pvwattsv8" 2>/dev/null || echo "WARNING: PySAM not available"

# Create a quickstart guide so the agent can discover available tools
cat > /home/ga/SAM_QUICKSTART.txt << 'QUICKSTART'
NREL System Advisor Model (SAM) Environment
============================================

Available tools:
  - SAM Desktop: GUI application (already open)
  - PySAM: Python SDK for SAM (pip package: NREL-PySAM)
    Example: python3 -c "import PySAM; print(PySAM.__version__)"

Weather data:
  - TMY weather files are in the SAM installation under solar_resource/
  - Check: cat /home/ga/.SAM/solar_resource_dir.txt

Output directory:
  - Save results to /home/ga/Documents/SAM_Projects/
QUICKSTART
chown ga:ga /home/ga/SAM_QUICKSTART.txt

# ============================================================
# Launch SAM GUI and dismiss registration dialog
# ============================================================
if [ -n "$SAM_DIR" ]; then
    echo "Launching SAM GUI from $SAM_DIR..."

    # Launch SAM as ga user with correct LD_LIBRARY_PATH
    su - ga -c "DISPLAY=:1 LD_LIBRARY_PATH='${SAM_DIR}/linux_64:${SAM_DIR}:\$LD_LIBRARY_PATH' /usr/local/bin/sam > /tmp/sam_gui.log 2>&1 &"
    sleep 5

    # Wait for the registration dialog window to appear (up to 15 seconds)
    REG_FOUND="false"
    for i in $(seq 1 15); do
        # Check for any SAM-related window
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sam\|registration\|system advisor"; then
            REG_FOUND="true"
            echo "SAM window detected after ${i}s"
            break
        fi
        sleep 1
    done

    if [ "$REG_FOUND" = "true" ]; then
        sleep 2

        # Dismiss the Registration dialog by clicking "Skip for Launch SAM" link
        # This link is at the bottom-right of the dialog. We use window geometry
        # to calculate its position reliably.
        REG_GEOM=$(DISPLAY=:1 wmctrl -lG 2>/dev/null | grep -i "registration" | head -1)
        if [ -n "$REG_GEOM" ]; then
            REG_X=$(echo "$REG_GEOM" | awk '{print $3}')
            REG_Y=$(echo "$REG_GEOM" | awk '{print $4}')
            REG_W=$(echo "$REG_GEOM" | awk '{print $5}')
            REG_H=$(echo "$REG_GEOM" | awk '{print $6}')
            # "Skip for Launch SAM" link is near bottom-right of dialog
            # approximately 85% across and 88% down
            SKIP_X=$((REG_X + REG_W * 85 / 100))
            SKIP_Y=$((REG_Y + REG_H * 88 / 100))
            echo "Clicking 'Skip for Launch SAM' at ($SKIP_X, $SKIP_Y) [dialog at ${REG_X},${REG_Y} ${REG_W}x${REG_H}]"
            DISPLAY=:1 xdotool mousemove "$SKIP_X" "$SKIP_Y" click 1 2>/dev/null || true
            sleep 3
        else
            # Fallback: try absolute coordinates for 1920x1080 screen
            echo "Could not get dialog geometry, trying absolute coordinates..."
            DISPLAY=:1 xdotool mousemove 1188 701 click 1 2>/dev/null || true
            sleep 3
        fi

        # Verify dialog was dismissed
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "registration"; then
            echo "Registration dialog still present after click, trying Escape..."
            DISPLAY=:1 xdotool key Escape 2>/dev/null || true
            sleep 1
        fi

        # Final fallback: close the registration window via wmctrl
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "registration"; then
            echo "Trying wmctrl close on registration dialog..."
            REG_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "registration" | awk '{print $1}' | head -1)
            if [ -n "$REG_WID" ]; then
                DISPLAY=:1 wmctrl -ic "$REG_WID" 2>/dev/null || true
            fi
            sleep 1
        fi

        echo "SAM GUI setup complete - registration dialog handled"
    else
        echo "WARNING: No SAM window appeared after 15 seconds"
    fi
else
    echo "WARNING: SAM_DIR not found, cannot launch GUI"
fi

# ============================================================
# Open a terminal for the agent to use (after SAM GUI setup so it's on top)
# ============================================================
su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
sleep 3

# Take a screenshot showing the current state
DISPLAY=:1 import -window root /tmp/sam_startup.png 2>/dev/null || true

chown -R ga:ga /home/ga/.SAM /home/ga/Desktop /home/ga/Documents 2>/dev/null || true

echo "=== SAM setup complete ==="
