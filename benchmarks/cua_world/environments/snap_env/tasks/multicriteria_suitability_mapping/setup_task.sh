#!/bin/bash
# Setup for multicriteria_suitability_mapping task
# Ensures both Landsat and DEM data are available, launches SNAP clean

set -e

# Source shared utilities if available
if [ -f /workspace/utils/task_utils.sh ]; then
    source /workspace/utils/task_utils.sh
fi

echo "=== Setting up multicriteria_suitability_mapping task ==="

# ── 1. Clean previous outputs ──
echo "Cleaning previous outputs..."
rm -rf /home/ga/snap_projects/*
rm -f /home/ga/snap_exports/*.tif /home/ga/snap_exports/*.dim /home/ga/snap_exports/*.nc
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# ── 2. Record task start timestamp (AFTER cleanup) ──
date +%s > /tmp/suitability_task_start_ts

# ── 3. Ensure data files exist ──
echo "Checking data files..."
mkdir -p /home/ga/snap_data

if [ ! -f /home/ga/snap_data/landsat_multispectral.tif ]; then
    echo "Downloading Landsat multispectral..."
    wget -q -O /home/ga/snap_data/landsat_multispectral.tif \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif"
    chown ga:ga /home/ga/snap_data/landsat_multispectral.tif
fi

if [ ! -f /home/ga/snap_data/srtm_dem.tif ]; then
    echo "Downloading SRTM DEM..."
    wget -q -O /home/ga/snap_data/srtm_dem.tif \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/dem.tif"
    chown ga:ga /home/ga/snap_data/srtm_dem.tif
fi

echo "Data files ready."

# ── 4. Kill any existing SNAP instances ──
echo "Killing existing SNAP..."
if type kill_snap &>/dev/null; then
    kill_snap ga
else
    pkill -u ga -f "/opt/snap/jre/bin/java" 2>/dev/null || true
    pkill -u ga -f "org.esa.snap" 2>/dev/null || true
    pkill -u ga -f "nbexec.*snap" 2>/dev/null || true
fi
sleep 3

# ── 5. Launch SNAP ──
echo "Launching SNAP..."
if type launch_snap &>/dev/null; then
    launch_snap
else
    cat > /tmp/launch_snap_now.sh << 'SNAPEOF'
#!/bin/bash
export DISPLAY=:1
export _JAVA_AWT_WM_NONREPARENTING=1
/opt/snap/bin/snap --nosplash > /tmp/snap_task.log 2>&1 &
SNAPEOF
    chmod +x /tmp/launch_snap_now.sh
    su - ga -c "bash /tmp/launch_snap_now.sh"
fi

# ── 6. Wait for SNAP window ──
echo "Waiting for SNAP to start..."
if type wait_for_snap_ready &>/dev/null; then
    wait_for_snap_ready 120 || { echo "ERROR: SNAP did not start"; exit 1; }
else
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
            echo "SNAP window detected after $((i*2))s"
            break
        fi
        sleep 2
    done
    sleep 5
fi

# ── 7. Dismiss startup dialogs ──
echo "Dismissing dialogs..."
if type dismiss_snap_dialogs &>/dev/null; then
    dismiss_snap_dialogs
else
    sleep 5
    DISPLAY=:1 xdotool mousemove 737 569 click 1 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool mousemove 1131 605 click 1 2>/dev/null || true
    sleep 2
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
fi

# ── 8. Maximize and focus SNAP window ──
echo "Maximizing SNAP window..."
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

# ── 9. Do NOT pre-open any files ──
# The agent must open both landsat_multispectral.tif and srtm_dem.tif
# as part of the task workflow (needed for collocation setup)

# ── 10. Take start screenshot ──
echo "Taking start screenshot..."
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/suitability_task_start_screenshot.png
else
    DISPLAY=:1 scrot /tmp/suitability_task_start_screenshot.png 2>/dev/null || true
fi

echo "=== Setup complete ==="
