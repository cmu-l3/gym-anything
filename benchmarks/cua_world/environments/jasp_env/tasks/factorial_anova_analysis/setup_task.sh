#!/bin/bash
echo "=== Setting up factorial_anova_analysis task ==="

# Kill any running JASP instance
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 3

# Ensure directories exist
mkdir -p /home/ga/Documents/JASP

# ------------------------------------------------------------------
# Copy Tooth Growth dataset from the JASP flatpak Data Library.
# The dataset lives inside the flatpak installation under a long
# content-addressed path. We use a glob to find it reliably.
# ------------------------------------------------------------------
DATASET="/home/ga/Documents/JASP/ToothGrowth.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying Tooth Growth dataset..."

    # Primary: copy from the flatpak Data Library (authoritative source)
    FLATPAK_DATA_DIR="/var/lib/flatpak/app/org.jaspstats.JASP/x86_64/stable"
    SRC_FILE=$(find "$FLATPAK_DATA_DIR" -path "*/Data Sets/Data Library/3. ANOVA/Tooth Growth.csv" 2>/dev/null | head -1)

    if [ -n "$SRC_FILE" ] && [ -f "$SRC_FILE" ]; then
        cp "$SRC_FILE" "$DATASET"
        echo "Copied from flatpak Data Library: $SRC_FILE"
    elif [ -f "/opt/jasp_datasets/Tooth Growth.csv" ]; then
        # Fallback: pre-downloaded copy from install_jasp.sh
        cp "/opt/jasp_datasets/Tooth Growth.csv" "$DATASET"
        echo "Copied from /opt/jasp_datasets/"
    else
        echo "ERROR: Tooth Growth dataset not found in flatpak or /opt/jasp_datasets/"
        echo "Attempting direct download from JASP GitHub..."
        wget -q -O "$DATASET" \
            "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/3.%20ANOVA/Tooth%20Growth.csv" || {
            echo "ERROR: Failed to download Tooth Growth dataset"
            exit 1
        }
    fi

    chown ga:ga "$DATASET"
fi

# Validate dataset
if [ ! -f "$DATASET" ]; then
    echo "ERROR: Dataset not found at $DATASET"
    exit 1
fi

FILE_SIZE=$(stat -c%s "$DATASET" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -lt 100 ]; then
    echo "ERROR: Dataset file too small (${FILE_SIZE} bytes)"
    exit 1
fi

echo "Dataset ready: $DATASET (${FILE_SIZE} bytes)"
echo "First 3 lines:"
head -3 "$DATASET"

# Record baseline: confirm no .jasp output file exists yet
JASP_OUTPUT="/home/ga/Documents/JASP/tooth_growth_anova.jasp"
rm -f "$JASP_OUTPUT" 2>/dev/null || true
echo "Baseline: no .jasp output file at $JASP_OUTPUT"

# Record task start timestamp
date +%s > /tmp/factorial_anova_task_start.ts
echo "Task start timestamp: $(cat /tmp/factorial_anova_task_start.ts)"

# ------------------------------------------------------------------
# Launch JASP with the dataset pre-loaded.
# Uses setsid so the process survives when su exits.
# QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox is set inside the launcher.
# ------------------------------------------------------------------
echo "Launching JASP with ToothGrowth.csv..."
su - ga -c "setsid /usr/local/bin/launch-jasp $DATASET > /tmp/jasp_task.log 2>&1 &"
sleep 22

# Dismiss any startup dialogs (update check, welcome, etc.)
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Maximize the JASP window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "=== factorial_anova_analysis task setup complete ==="
