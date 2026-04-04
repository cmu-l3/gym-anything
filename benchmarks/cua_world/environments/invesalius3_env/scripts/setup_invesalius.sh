#!/bin/bash
set -e

echo "=== Setting up InVesalius 3 ==="

wait_for_x() {
    local timeout=${1:-60}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 xset q >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

dicom_payload_present() {
    # Returns success if $1 contains at least one DICOM file (by extension, or via DCMTK inspection).
    local root="$1"

    if find "$root" -type f \( -iname "*.dcm" -o -iname "*.dicom" -o -iname "*.ima" \) -print -quit 2>/dev/null | grep -q .; then
        return 0
    fi

    if command -v dcmdump >/dev/null 2>&1; then
        while IFS= read -r candidate; do
            if dcmdump "$candidate" >/dev/null 2>&1; then
                return 0
            fi
        done < <(find "$root" -type f 2>/dev/null | head -n 50)
        return 1
    fi

    # Last resort: accept presence of any files.
    find "$root" -type f -print -quit 2>/dev/null | grep -q .
}

if ! wait_for_x 60; then
    echo "X display not ready after timeout."
fi

# Create InVesalius launcher wrapper for consistent command
cat > /usr/local/bin/invesalius-launch << 'LAUNCHEOF'
#!/bin/bash
set -e

if command -v invesalius3 >/dev/null 2>&1; then
    exec invesalius3 "$@"
elif command -v invesalius >/dev/null 2>&1; then
    exec invesalius "$@"
elif command -v flatpak >/dev/null 2>&1 && flatpak info br.gov.cti.invesalius >/dev/null 2>&1; then
    exec flatpak run br.gov.cti.invesalius "$@"
else
    echo "InVesalius is not installed or not found in PATH." >&2
    exit 1
fi
LAUNCHEOF
chmod +x /usr/local/bin/invesalius-launch

# If InVesalius was installed via Flatpak, ensure it can read the sample dataset.
# (Flatpak sandbox permissions can vary by build; this keeps imports deterministic.)
if command -v flatpak >/dev/null 2>&1 && flatpak info br.gov.cti.invesalius >/dev/null 2>&1; then
    flatpak override --system --filesystem=home --filesystem=/opt/invesalius br.gov.cti.invesalius >/dev/null 2>&1 || true
fi

# Prepare sample data directory
SAMPLE_ROOT="/opt/invesalius/sample_data"
CRANIUM_DIR="$SAMPLE_ROOT/ct_cranium"
# Source: https://invesalius.github.io/download/
# The download page currently points CT Cranium to the v3.0 asset "0051.zip".
CRANIUM_URL="https://github.com/invesalius/invesalius3/releases/download/v3.0/0051.zip"

mkdir -p "$CRANIUM_DIR"

if ! dicom_payload_present "$CRANIUM_DIR"; then
    echo "Downloading CT Cranium DICOM sample..."
    tmp_dir=$(mktemp -d)
    if curl -L --fail --retry 3 --connect-timeout 20 --max-time 300 \
        -o "$tmp_dir/ct_cranium.zip" "$CRANIUM_URL"; then
        unzip -q -o "$tmp_dir/ct_cranium.zip" -d "$CRANIUM_DIR"
    elif wget --timeout=300 -O "$tmp_dir/ct_cranium.zip" "$CRANIUM_URL"; then
        unzip -q -o "$tmp_dir/ct_cranium.zip" -d "$CRANIUM_DIR"
    else
        echo "Failed to download CT Cranium DICOM sample." >&2
    fi
    rm -rf "$tmp_dir"
fi

if ! dicom_payload_present "$CRANIUM_DIR"; then
    echo "CT Cranium DICOM sample is missing after download attempts." >&2
    exit 1
fi

cat > "$SAMPLE_ROOT/SOURCES.txt" << EOF
CT Cranium DICOM dataset source:
$CRANIUM_URL
EOF

# Set permissions for ga user
mkdir -p /home/ga/DICOM
ln -sfn "$CRANIUM_DIR" /home/ga/DICOM/ct_cranium
chown -R ga:ga /opt/invesalius /home/ga/DICOM

# Create desktop launcher for ga
cat > /home/ga/Desktop/InVesalius.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=InVesalius 3
Comment=3D reconstruction from DICOM images
Exec=/home/ga/launch_invesalius.sh
Icon=utilities-terminal
StartupNotify=true
Terminal=false
Categories=Graphics;MedicalSoftware;Science;
Type=Application
DESKTOPEOF
chown ga:ga /home/ga/Desktop/InVesalius.desktop
chmod +x /home/ga/Desktop/InVesalius.desktop

# Create launch script for ga user
cat > /home/ga/launch_invesalius.sh << 'LAUNCHSCRIPT'
#!/bin/bash
export DISPLAY=${DISPLAY:-:1}

xhost +local: >/dev/null 2>&1 || true

/usr/local/bin/invesalius-launch "$@" > /tmp/invesalius_$USER.log 2>&1 &
LAUNCHSCRIPT
chown ga:ga /home/ga/launch_invesalius.sh
chmod +x /home/ga/launch_invesalius.sh

# Evidence/debug screenshot: the desktop state immediately after post_start.
DISPLAY=:1 scrot /tmp/env_post_start.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/env_post_start.png 2>/dev/null || true

echo "=== InVesalius setup complete ==="
