#!/bin/bash
set -euo pipefail

echo "=== Setting up Gretl ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# =====================================================================
# 1. Set up user directories
# =====================================================================
mkdir -p /home/ga/Documents/gretl_data
mkdir -p /home/ga/Documents/gretl_output
chown -R ga:ga /home/ga/Documents

# =====================================================================
# 2. Copy datasets to user's Documents folder
# =====================================================================
echo "Copying datasets to user home..."
cp /opt/gretl_data/poe5/food.gdt /home/ga/Documents/gretl_data/ 2>/dev/null || true
cp /opt/gretl_data/poe5/usa.gdt  /home/ga/Documents/gretl_data/ 2>/dev/null || true

# Copy additional POE5 datasets if available
for ds in cps5_small.gdt cps5.gdt mroz.gdt bwght.gdt wage1.gdt andy.gdt; do
    [ -f "/opt/gretl_data/poe5/$ds" ] && cp "/opt/gretl_data/poe5/$ds" /home/ga/Documents/gretl_data/ 2>/dev/null || true
done

# Also copy all datasets from built-in gretl if available
if [ -d /usr/share/gretl/data ]; then
    find /usr/share/gretl/data -name "*.gdt" -exec cp {} /home/ga/Documents/gretl_data/ \; 2>/dev/null || true
fi

chown -R ga:ga /home/ga/Documents/gretl_data
chmod 755 /home/ga/Documents/gretl_data
chmod 644 /home/ga/Documents/gretl_data/*.gdt 2>/dev/null || true

GDT_INSTALLED=$(ls /home/ga/Documents/gretl_data/*.gdt 2>/dev/null | wc -l)
echo "Datasets installed: $GDT_INSTALLED .gdt files"
ls /home/ga/Documents/gretl_data/*.gdt 2>/dev/null | head -10 | while read f; do echo "  $(basename "$f")"; done || echo "  (no .gdt files found)"

# =====================================================================
# 3. Pre-configure Gretl to suppress first-run dialogs
# Gretl stores preferences in ~/.gretl/gretlrc (Linux)
# Key: disable tip-of-day, update checks, autofit notification
# =====================================================================
mkdir -p /home/ga/.gretl

cat > /home/ga/.gretl/gretlrc << 'GRETLRC_EOF'
# Gretl preferences - pre-configured to suppress first-run dialogs
tipofday = 0
updatedURL = 1
autofit_font = 0
verbose_include = 0
HC_use_robust = 0
main_toolbar_visible = 1
show_iface_tooltip = 0
native_pdfviewer = 0
GRETLRC_EOF

chown -R ga:ga /home/ga/.gretl
chmod 644 /home/ga/.gretl/gretlrc

# =====================================================================
# 4. Create Desktop shortcut
# =====================================================================
mkdir -p /home/ga/Desktop

cat > /home/ga/Desktop/Gretl.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Name=Gretl
Comment=GNU Regression, Econometrics and Time-series Library
Exec=gretl
Icon=gretl
Type=Application
Categories=Science;Math;Education;
Terminal=false
DESKTOP_EOF

chown ga:ga /home/ga/Desktop/Gretl.desktop
chmod +x /home/ga/Desktop/Gretl.desktop

# Mark as trusted so GNOME doesn't ask for confirmation
sleep 1
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    gio set /home/ga/Desktop/Gretl.desktop 'metadata::trusted' true 2>/dev/null" || true

# =====================================================================
# 5. Warm-up launch: start Gretl once to accept any first-run dialogs
#    and ensure preferences are persisted
# =====================================================================
echo "Performing warm-up launch to dismiss any first-run dialogs..."

xhost +local: 2>/dev/null || true

# Launch Gretl briefly as ga user
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid gretl /home/ga/Documents/gretl_data/food.gdt \
    >/home/ga/gretl_warmup.log 2>&1 &"
sleep 8

# Dismiss any tip-of-day or welcome dialogs with Escape/Enter
for i in {1..5}; do
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        xdotool key Return 2>/dev/null || true
    sleep 1
done

# Check if Gretl window is visible
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "gretl"; then
    echo "Gretl window detected during warm-up."
    # Take a warm-up screenshot to confirm state
    DISPLAY=:1 scrot /tmp/gretl_warmup_screen.png 2>/dev/null || true
else
    echo "WARNING: Gretl window not detected during warm-up (may be launching slowly)"
fi

# Kill warm-up instance cleanly
pkill -f "gretl " 2>/dev/null || true
pkill -f "gretl$" 2>/dev/null || true
sleep 3

# =====================================================================
# 6. Verify setup
# =====================================================================
echo "Dataset verification:"
for ds in food.gdt usa.gdt; do
    if [ -f "/home/ga/Documents/gretl_data/$ds" ]; then
        echo "  [OK] $ds ($(stat -c%s /home/ga/Documents/gretl_data/$ds) bytes)"
    else
        echo "  [MISSING] $ds"
    fi
done

echo "=== Gretl setup complete ==="
