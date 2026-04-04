#!/bin/bash
set -e

echo "=== Setting up PyMOL environment ==="

# Wait for desktop to be ready
sleep 5

setup_user_pymol() {
    local USERNAME="$1"
    local HOME_DIR="$2"

    echo "Setting up PyMOL for user: ${USERNAME}"

    # Create PyMOL data directories
    mkdir -p "${HOME_DIR}/PyMOL_Data/structures"
    mkdir -p "${HOME_DIR}/PyMOL_Data/sessions"
    mkdir -p "${HOME_DIR}/PyMOL_Data/images"
    mkdir -p "${HOME_DIR}/Documents"
    mkdir -p "${HOME_DIR}/Desktop"

    # Copy PDB files to user directory
    if [ -d /opt/pymol_data/structures ]; then
        cp /opt/pymol_data/structures/*.pdb "${HOME_DIR}/PyMOL_Data/structures/" 2>/dev/null || true
    fi

    # Create pymolrc to suppress first-run behaviors and set defaults
    cat > "${HOME_DIR}/.pymolrc" << 'PYMOLRC'
# PyMOL startup configuration
# Suppress splash and set defaults for clean startup
set internal_gui, 1
set internal_gui_width, 250
set internal_feedback, 1
set text, 0
set auto_show_lines, 0
set auto_show_nonbonded, 0
set auto_zoom, 1
set bg_rgb, [0, 0, 0]
set ray_opaque_background, 1
set orthoscopic, 0
set depth_cue, 1
set spec_reflect, 1.5
set spec_power, 200
PYMOLRC

    # Create launch script
    cat > "${HOME_DIR}/Desktop/launch_pymol.sh" << 'LAUNCH'
#!/bin/bash
export DISPLAY=:1
export QT_QPA_PLATFORM=xcb
pymol -q "$@" &
LAUNCH
    chmod +x "${HOME_DIR}/Desktop/launch_pymol.sh"

    # Create .desktop shortcut
    cat > "${HOME_DIR}/Desktop/pymol.desktop" << 'DESKTOP'
[Desktop Entry]
Type=Application
Name=PyMOL
Comment=Molecular Visualization System
Exec=pymol -q
Icon=pymol
Terminal=false
Categories=Science;Biology;
DESKTOP
    chmod +x "${HOME_DIR}/Desktop/pymol.desktop"

    # Create pymol-info utility
    cat > /usr/local/bin/pymol-info << 'INFO'
#!/bin/bash
echo "=== PyMOL Environment Info ==="
echo "PyMOL binary: $(which pymol)"
echo "PDB structures: $(ls /home/ga/PyMOL_Data/structures/*.pdb 2>/dev/null | wc -l) files"
echo "Available PDB files:"
ls -la /home/ga/PyMOL_Data/structures/*.pdb 2>/dev/null
echo ""
echo "PyMOL config: /home/ga/.pymolrc"
echo "=== End Info ==="
INFO
    chmod +x /usr/local/bin/pymol-info

    # Fix ownership
    chown -R "${USERNAME}:${USERNAME}" "${HOME_DIR}/PyMOL_Data"
    chown -R "${USERNAME}:${USERNAME}" "${HOME_DIR}/Desktop"
    chown -R "${USERNAME}:${USERNAME}" "${HOME_DIR}/Documents"
    chown "${USERNAME}:${USERNAME}" "${HOME_DIR}/.pymolrc"

    echo "PyMOL setup complete for user: ${USERNAME}"
}

# Setup for ga user
if id "ga" &>/dev/null; then
    setup_user_pymol "ga" "/home/ga"
fi

# Warm-up launch: start PyMOL once to clear any first-run state, then close
echo "=== Warm-up launch to clear first-run state ==="
su - ga -c "DISPLAY=:1 QT_QPA_PLATFORM=xcb setsid pymol -q > /tmp/pymol_warmup.log 2>&1 &"
WARMUP_PID=$!

# Wait for PyMOL window to appear
for i in $(seq 1 30); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "pymol" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "PyMOL window detected: ${WID}"
        break
    fi
    sleep 1
done

# Give it a moment for any dialogs to appear, then close
sleep 3

# Close PyMOL
pkill -f "pymol" 2>/dev/null || true
sleep 2

echo "=== PyMOL environment setup complete ==="
