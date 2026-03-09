#!/bin/bash
# Do NOT use set -e — robust error handling is needed for warm-up launch and dialog dismissal

echo "=== Setting up Stellarium environment ==="

# ── 1. Wait for desktop to be ready ──────────────────────────────────
sleep 5

# ── 2. Pre-configure Stellarium to suppress first-run wizard ─────────
# The config.ini must include [init_location] landscape_name = guereins
# to ensure the LandscapeMgr creates a landscape object during init.
# Without this, Stellarium crashes with a NULL pointer dereference.
STEL_DIR="/home/ga/.stellarium"
mkdir -p "$STEL_DIR"
cp /workspace/config/config.ini "$STEL_DIR/config.ini"
chown -R ga:ga "$STEL_DIR"

# ── 3. Create directories for screenshots and exports ────────────────
mkdir -p /home/ga/Pictures/stellarium
chown -R ga:ga /home/ga/Pictures

# ── 4. Copy real data files to user-accessible location ──────────────
mkdir -p /home/ga/data
cp /workspace/data/*.json /home/ga/data/ 2>/dev/null || true
chown -R ga:ga /home/ga/data

# ── 5. Create launch script BEFORE warm-up ───────────────────────────
cat > /home/ga/start_stellarium.sh << 'STELSCRIPT'
#!/bin/bash
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export MESA_GL_VERSION_OVERRIDE=4.5COMPAT
export MESA_GLSL_VERSION_OVERRIDE=450
setsid stellarium > /tmp/stellarium.log 2>&1 &
echo $! > /tmp/stellarium.pid
STELSCRIPT

chmod +x /home/ga/start_stellarium.sh
chown ga:ga /home/ga/start_stellarium.sh

# ── 6. Copy utility scripts to user home ─────────────────────────────
cp /workspace/scripts/task_utils.sh /home/ga/task_utils.sh
chown ga:ga /home/ga/task_utils.sh

# ── 7. Warm-up launch to clear first-run state ──────────────────────
echo "--- Warm-up launch of Stellarium ---"
su - ga -c "bash /home/ga/start_stellarium.sh"

# Wait for Stellarium window to appear (llvmpipe is slow, allow 120s)
ELAPSED=0
while [ $ELAPSED -lt 120 ]; do
    WID=$(DISPLAY=:1 xdotool search --name "Stellarium" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        echo "Stellarium window found (WID=$WID)"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if [ $ELAPSED -ge 120 ]; then
    echo "WARNING: Stellarium window not detected within 120s"
    echo "--- Stellarium log ---"
    cat /tmp/stellarium.log 2>/dev/null | tail -20 || true
fi

# Give it time to fully render (llvmpipe needs more time)
sleep 15

# Dismiss any first-run dialogs (press Escape multiple times)
for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Close the warm-up instance
echo "--- Closing warm-up instance ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true

# Wait for it to fully close
sleep 3

echo "=== Stellarium setup complete ==="
echo "Stellarium log: /tmp/stellarium.log"
echo "Launch with: bash /home/ga/start_stellarium.sh"
