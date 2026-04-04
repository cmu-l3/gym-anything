#!/bin/bash
set -euo pipefail

echo "=== Setting up GMAT ==="

# Wait for desktop to be ready
sleep 5

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Find the GMAT GUI binary (handles versioned names like GMAT-R2022a)
GMAT_GUI=""
for candidate in /opt/GMAT/bin/GMAT_Beta /opt/GMAT/bin/GMAT-R2022a /opt/GMAT/bin/GMAT-R2020a /opt/GMAT/bin/GMAT-R2025a /opt/GMAT/bin/GMAT; do
    if [ -f "$candidate" ] && file "$candidate" | grep -q "ELF"; then
        GMAT_GUI="$candidate"
        break
    fi
done

if [ -z "$GMAT_GUI" ]; then
    echo "WARNING: No GUI binary found by name, searching..."
    GMAT_GUI=$(find /opt/GMAT/bin -maxdepth 1 -name "GMAT*" -type f -executable 2>/dev/null | while read f; do
        if file "$f" | grep -q "ELF"; then echo "$f"; break; fi
    done)
fi

echo "GMAT GUI binary: ${GMAT_GUI:-NOT FOUND}"

# Find the console binary
GMAT_CONSOLE=""
for candidate in /opt/GMAT/bin/GmatConsole /opt/GMAT/bin/GmatConsole-R2022a /opt/GMAT/bin/GmatConsole-R2020a /opt/GMAT/bin/GmatConsole-R2025a; do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
        GMAT_CONSOLE="$candidate"
        break
    fi
done
echo "GMAT Console binary: ${GMAT_CONSOLE:-NOT FOUND}"

# Set up environment for GMAT
cat >> /home/ga/.bashrc << 'EOF'
export GMAT_ROOT=/opt/GMAT
export PATH=$GMAT_ROOT/bin:$PATH
export LD_LIBRARY_PATH=$GMAT_ROOT/bin:${LD_LIBRARY_PATH:-}
EOF

cat > /etc/profile.d/gmat.sh << 'EOF'
export GMAT_ROOT=/opt/GMAT
export PATH=$GMAT_ROOT/bin:$PATH
export LD_LIBRARY_PATH=$GMAT_ROOT/bin:${LD_LIBRARY_PATH:-}
EOF

# Create working directories
mkdir -p /home/ga/GMAT_output /home/ga/Documents/missions
chown ga:ga /home/ga/GMAT_output /home/ga/Documents/missions

# Copy sample missions to user's working directory (real NASA mission data)
if [ -d "/opt/GMAT/samples" ]; then
    cp -r /opt/GMAT/samples/* /home/ga/Documents/missions/ 2>/dev/null || true
    chown -R ga:ga /home/ga/Documents/missions/
    echo "Copied $(find /home/ga/Documents/missions -name '*.script' | wc -l) sample missions"
fi

# Create a launcher script that correctly finds the binary
cat > /home/ga/launch_gmat.sh << 'LAUNCHEOF'
#!/bin/bash
export DISPLAY=:1
export GMAT_ROOT=/opt/GMAT
export LD_LIBRARY_PATH=/opt/GMAT/bin:${LD_LIBRARY_PATH:-}
cd /opt/GMAT/bin

# Find the GUI binary dynamically
GMAT_BIN=""
for candidate in GMAT_Beta GMAT-R2022a GMAT-R2020a GMAT-R2025a GMAT; do
    if [ -f "$candidate" ] && file "$candidate" | grep -q "ELF"; then
        GMAT_BIN="./$candidate"
        break
    fi
done

if [ -z "$GMAT_BIN" ]; then
    echo "ERROR: Could not find GMAT binary"
    exit 1
fi

exec $GMAT_BIN "$@"
LAUNCHEOF
chmod +x /home/ga/launch_gmat.sh
chown ga:ga /home/ga/launch_gmat.sh

# Create desktop entry
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/GMAT.desktop << 'DSKEOF'
[Desktop Entry]
Name=GMAT
Comment=NASA General Mission Analysis Tool
Exec=/home/ga/launch_gmat.sh
Icon=/opt/GMAT/data/graphics/splash/GMATSplashScreen.png
Terminal=false
Type=Application
Categories=Science;Education;
DSKEOF
chmod +x /home/ga/Desktop/GMAT.desktop
chown ga:ga /home/ga/Desktop/GMAT.desktop

# Block GMAT's browser-opening behavior (it tries to open gmatcentral.org on startup)
echo "127.0.0.1 gmatcentral.org" >> /etc/hosts
echo "127.0.0.1 www.gmatcentral.org" >> /etc/hosts

# Warm-up launch: Start GMAT once to trigger any first-run initialization
echo "=== Performing warm-up launch of GMAT ==="
if [ -n "$GMAT_GUI" ]; then
    su - ga -c "cd /opt/GMAT/bin && DISPLAY=:1 LD_LIBRARY_PATH=/opt/GMAT/bin:\${LD_LIBRARY_PATH:-} setsid $GMAT_GUI > /tmp/gmat_warmup.log 2>&1 &"

    # Wait for GMAT window to appear
    GMAT_FOUND=false
    for i in $(seq 1 30); do
        WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "GMAT" 2>/dev/null | head -1)
        if [ -n "$WID" ]; then
            GMAT_FOUND=true
            echo "GMAT window appeared after $((i * 2)) seconds"
            break
        fi
        sleep 2
    done

    if [ "$GMAT_FOUND" = "true" ]; then
        sleep 3
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return 2>/dev/null || true
        sleep 1
    else
        echo "WARNING: GMAT window did not appear within 60 seconds"
        cat /tmp/gmat_warmup.log 2>/dev/null | tail -10 || true
    fi

    # Kill warm-up instance and any Firefox that GMAT may have opened
    pkill -f "GMAT" 2>/dev/null || true
    pkill -f "firefox" 2>/dev/null || true
    sleep 2
    pkill -9 -f "GMAT" 2>/dev/null || true
    pkill -9 -f "firefox" 2>/dev/null || true
    echo "GMAT warm-up launch complete"
else
    echo "WARNING: Skipping warm-up launch - no GUI binary found"
fi

echo "=== GMAT Setup Summary ==="
echo "GMAT root: /opt/GMAT"
echo "GUI binary: ${GMAT_GUI:-NOT FOUND}"
echo "Console binary: ${GMAT_CONSOLE:-NOT FOUND}"
echo "Sample missions: $(find /home/ga/Documents/missions -name '*.script' 2>/dev/null | wc -l) scripts"

echo "=== GMAT setup complete ==="
