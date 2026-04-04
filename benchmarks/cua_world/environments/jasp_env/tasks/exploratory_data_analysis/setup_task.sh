#!/bin/bash
echo "=== Setting up exploratory_data_analysis task ==="

# Kill any running JASP instance
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 3

# Ensure the JASP working directory exists
mkdir -p /home/ga/Documents/JASP

# Copy the penguins dataset from JASP's bundled Data Library
# The Data Library is inside the Flatpak installation directory.
JASP_DATA_LIB="/var/lib/flatpak/app/org.jaspstats.JASP/x86_64/stable/active/files/Resources/Data Sets"
PENGUINS_SRC="${JASP_DATA_LIB}/Data Library/10. Machine Learning/penguins.csv"
DATASET="/home/ga/Documents/JASP/penguins.csv"

if [ -f "$PENGUINS_SRC" ]; then
    echo "Copying penguins.csv from JASP Data Library..."
    cp "$PENGUINS_SRC" "$DATASET"
else
    # Fallback: try the exact hash path from env description
    JASP_DATA_LIB_ALT="/var/lib/flatpak/app/org.jaspstats.JASP/x86_64/stable/d20ad827ec98eed73eb94ccc2dba10c7ee0206b2d3be2317f5fdecac8cf82ac1/files/Resources/Data Sets"
    PENGUINS_SRC_ALT="${JASP_DATA_LIB_ALT}/Data Library/10. Machine Learning/penguins.csv"
    if [ -f "$PENGUINS_SRC_ALT" ]; then
        echo "Copying penguins.csv from JASP Data Library (alt path)..."
        cp "$PENGUINS_SRC_ALT" "$DATASET"
    else
        # Last resort: search for it
        echo "Searching for penguins.csv in flatpak paths..."
        FOUND=$(find /var/lib/flatpak -name "penguins.csv" -path "*/Machine Learning/*" 2>/dev/null | head -1)
        if [ -n "$FOUND" ]; then
            echo "Found at: $FOUND"
            cp "$FOUND" "$DATASET"
        else
            echo "ERROR: penguins.csv not found in JASP Data Library"
            echo "Creating fallback penguins dataset from known data..."
            # This should not happen if JASP is properly installed, but provide a safety net
            exit 1
        fi
    fi
fi

chown ga:ga "$DATASET"
chmod 644 "$DATASET"

echo "Dataset ready: $DATASET"
head -3 "$DATASET"
wc -l "$DATASET"

# Remove any previous output file so we start clean
rm -f /home/ga/Documents/JASP/penguins_eda.jasp

# Record baseline timestamp for verifier
date +%s > /tmp/eda_task_start_timestamp

# Open JASP with the penguins dataset pre-loaded.
# Uses setsid so the process survives when su exits.
# QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox is set inside the launcher script.
su - ga -c "setsid /usr/local/bin/launch-jasp $DATASET > /tmp/jasp_task.log 2>&1 &"
sleep 22

# Dismiss any dialogs (e.g. check-for-updates dialog)
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Maximize window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "=== exploratory_data_analysis task setup complete ==="
