#!/bin/bash
set -e

echo "=== Setting up KStars + INDI environment ==="

# ── 1. Wait for desktop to be ready ──────────────────────────────────
sleep 5

# ── 2. Set GSC environment for CCD simulator star field rendering ────
# The CCD Simulator queries the Hubble Guide Star Catalog to render
# scientifically accurate star fields based on current telescope pointing
echo 'export GSCDAT=/usr/share/GSC' >> /home/ga/.bashrc
echo 'export GSCDAT=/usr/share/GSC' >> /etc/environment

# ── 3. Pre-configure KStars to suppress first-run wizard ─────────────
mkdir -p /home/ga/.config
cp /workspace/config/kstarsrc /home/ga/.config/kstarsrc
chown ga:ga /home/ga/.config/kstarsrc

# ── 4. Create INDI config directory ──────────────────────────────────
mkdir -p /home/ga/.indi
chown -R ga:ga /home/ga/.indi

# ── 5. Create directories for captured images ────────────────────────
mkdir -p /home/ga/Images/{captures,sequences}
chown -R ga:ga /home/ga/Images

# ── 6. Start INDI server with observatory simulator drivers ──────────
# Telescope Simulator — virtual mount that slews (sky view moves in KStars)
# CCD Simulator — generates realistic star fields from GSC catalog
# Focuser Simulator — adjustable focus with visible defocus effects
# Filter Simulator — RGB/narrowband filter switching
echo "--- Starting INDI server with simulator drivers ---"

cat > /home/ga/start_indi.sh << 'INDISCRIPT'
#!/bin/bash
export GSCDAT=/usr/share/GSC

setsid indiserver -v \
    indi_simulator_telescope \
    indi_simulator_ccd \
    indi_simulator_focus \
    indi_simulator_wheel \
    > /tmp/indiserver.log 2>&1 &

echo $! > /tmp/indiserver.pid
INDISCRIPT

chmod +x /home/ga/start_indi.sh
chown ga:ga /home/ga/start_indi.sh

su - ga -c "bash /home/ga/start_indi.sh"

# Poll for INDI server to be ready (listening on port 7624)
echo "--- Waiting for INDI server ---"
ELAPSED=0
while [ $ELAPSED -lt 60 ]; do
    if ss -tlnp | grep -q ':7624'; then
        echo "INDI server is listening on port 7624"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge 60 ]; then
    echo "WARNING: INDI server may not have started. Check /tmp/indiserver.log"
    cat /tmp/indiserver.log 2>/dev/null || true
fi

# ── 7. Connect all simulator devices via INDI protocol ───────────────
echo "--- Connecting simulator devices ---"
sleep 2

indi_setprop "Telescope Simulator.CONNECTION.CONNECT=On" 2>/dev/null || true
sleep 1
indi_setprop "CCD Simulator.CONNECTION.CONNECT=On" 2>/dev/null || true
sleep 1
indi_setprop "Focuser Simulator.CONNECTION.CONNECT=On" 2>/dev/null || true
sleep 1
indi_setprop "Filter Simulator.CONNECTION.CONNECT=On" 2>/dev/null || true
sleep 1

# Configure CCD to save images locally
indi_setprop "CCD Simulator.UPLOAD_MODE.UPLOAD_LOCAL=On" 2>/dev/null || true
indi_setprop "CCD Simulator.UPLOAD_SETTINGS.UPLOAD_DIR=/home/ga/Images/captures" 2>/dev/null || true
indi_setprop "CCD Simulator.UPLOAD_SETTINGS.UPLOAD_PREFIX=sim_" 2>/dev/null || true

# Configure scope info for CCD simulator star field rendering
# Without focal length and aperture, the CCD simulator produces only noise
indi_setprop "CCD Simulator.SCOPE_INFO.FOCAL_LENGTH=750" 2>/dev/null || true
indi_setprop "CCD Simulator.SCOPE_INFO.APERTURE=200" 2>/dev/null || true

# Verify connections
echo "--- Device connection status ---"
indi_getprop "Telescope Simulator.CONNECTION.*" 2>/dev/null || true
indi_getprop "CCD Simulator.CONNECTION.*" 2>/dev/null || true
indi_getprop "Focuser Simulator.CONNECTION.*" 2>/dev/null || true
indi_getprop "Filter Simulator.CONNECTION.*" 2>/dev/null || true

# ── 8. Create KStars launch script ───────────────────────────────────
cat > /home/ga/start_kstars.sh << 'KSTARSSCRIPT'
#!/bin/bash
export DISPLAY=:1
export GSCDAT=/usr/share/GSC
export XAUTHORITY=/home/ga/.Xauthority
# D-Bus session bus — required for KStars D-Bus scripting (zoom, export, HiPS)
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

setsid kstars > /tmp/kstars.log 2>&1 &
echo $! > /tmp/kstars.pid
KSTARSSCRIPT

chmod +x /home/ga/start_kstars.sh
chown ga:ga /home/ga/start_kstars.sh

# ── 9. Launch KStars ─────────────────────────────────────────────────
echo "--- Launching KStars ---"
su - ga -c "bash /home/ga/start_kstars.sh"

# Wait for KStars window to appear
echo "--- Waiting for KStars window ---"
ELAPSED=0
while [ $ELAPSED -lt 60 ]; do
    if DISPLAY=:1 xdotool search --name "KStars" 2>/dev/null | head -1 | grep -q .; then
        echo "KStars window found"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if [ $ELAPSED -ge 60 ]; then
    echo "WARNING: KStars window not detected. Check /tmp/kstars.log"
    cat /tmp/kstars.log 2>/dev/null | tail -20 || true
fi

# ── 10. Dismiss any first-run dialogs ────────────────────────────────
sleep 5

# Press Escape a few times to dismiss any startup dialogs/tips
for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Maximize KStars window
DISPLAY=:1 wmctrl -r "KStars" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# ── 11. Verify KStars D-Bus interface is available ─────────────────────
# D-Bus allows programmatic control of KStars (centering, zooming, etc.)
# Sky capture uses the CDS hips2fits API for rendering real survey imagery
echo "--- Checking KStars D-Bus ---"
DBUS_ADDR="unix:path=/run/user/$(id -u ga)/bus"
if command -v qdbus &>/dev/null; then
    sleep 3
    if DISPLAY=:1 DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" qdbus org.kde.kstars /KStars 2>/dev/null | grep -q "setRaDec"; then
        echo "KStars D-Bus interface available"
    else
        echo "WARNING: KStars D-Bus not reachable"
    fi
fi

# Verify hips2fits API is reachable (used by capture_sky_view.sh)
echo "--- Checking CDS hips2fits API ---"
if curl -sf -o /dev/null "https://alasky.cds.unistra.fr/hips-image-services/hips2fits?hips=CDS%2FP%2FDSS2%2Fcolor&width=64&height=64&fov=1&ra=0&dec=0&projection=TAN&format=png" 2>/dev/null; then
    echo "CDS hips2fits API reachable"
else
    echo "WARNING: CDS hips2fits API not reachable — sky captures may fail"
fi

# Copy capture script to user home for easy access
cp /workspace/scripts/capture_sky_view.sh /home/ga/capture_sky_view.sh
chmod +x /home/ga/capture_sky_view.sh
chown ga:ga /home/ga/capture_sky_view.sh

cp /workspace/scripts/false_color.py /home/ga/false_color.py
chown ga:ga /home/ga/false_color.py

echo "=== KStars + INDI setup complete ==="
echo "INDI server log: /tmp/indiserver.log"
echo "KStars log: /tmp/kstars.log"

# Final status
echo "--- Running processes ---"
ps aux | grep -E "(indiserver|kstars|indi_simulator)" | grep -v grep || true
echo "--- Open windows ---"
DISPLAY=:1 wmctrl -l 2>/dev/null || true
