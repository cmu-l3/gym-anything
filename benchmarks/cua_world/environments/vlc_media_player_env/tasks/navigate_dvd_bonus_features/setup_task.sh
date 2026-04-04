#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up DVD Bonus Features Navigation Task ==="

kill_vlc ga
sleep 1

# Install dvdauthor if not present (needed for creating DVD structure)
if ! command -v dvdauthor &> /dev/null; then
    echo "Installing dvdauthor..."
    apt-get update -qq
    apt-get install -y -qq dvdauthor genisoimage > /dev/null 2>&1
fi

# Paths
ISO_PATH="/home/ga/Videos/sample_movie.iso"
DVD_SOURCE="/tmp/dvd_structure_$$"
WORK_DIR="/tmp/dvd_work_$$"

# Clean up any existing ISO
rm -f "$ISO_PATH"

# Create working directory
mkdir -p "$WORK_DIR"
mkdir -p "$DVD_SOURCE"

echo "Creating DVD structure with multiple titles..."

# Create three short video files for DVD titles
# Title 1: Main feature (15 seconds)
# Title 2: Bonus features (12 seconds) - TARGET
# Title 3: Deleted scenes (8 seconds)

# Use existing sample video as base, create shorter versions
if [ -f /home/ga/Videos/sample_video.mp4 ]; then
    # Create Title 1 (main feature) - 15 seconds
    ffmpeg -y -i /home/ga/Videos/sample_video.mp4 -t 15 -c:v mpeg2video -c:a mp2 -f mpeg -b:v 5000k \
        "$WORK_DIR/title1.mpg" > /dev/null 2>&1
    
    # Create Title 2 (bonus - target) - 12 seconds, slightly different
    ffmpeg -y -i /home/ga/Videos/sample_video.mp4 -ss 2 -t 12 -c:v mpeg2video -c:a mp2 -f mpeg -b:v 5000k \
        "$WORK_DIR/title2.mpg" > /dev/null 2>&1
    
    # Create Title 3 (extras) - 8 seconds
    ffmpeg -y -i /home/ga/Videos/sample_video.mp4 -ss 5 -t 8 -c:v mpeg2video -c:a mp2 -f mpeg -b:v 5000k \
        "$WORK_DIR/title3.mpg" > /dev/null 2>&1
else
    echo "ERROR: Sample video not found"
    exit 1
fi

# Create DVD authoring XML
cat > "$WORK_DIR/dvd.xml" <<'EOF'
<dvdauthor dest="/tmp/dvd_structure">
  <vmgm />
  <titleset>
    <titles>
      <pgc>
        <vob file="/tmp/dvd_work/title1.mpg" />
        <post>call menu;</post>
      </pgc>
      <pgc>
        <vob file="/tmp/dvd_work/title2.mpg" />
        <post>call menu;</post>
      </pgc>
      <pgc>
        <vob file="/tmp/dvd_work/title3.mpg" />
        <post>call menu;</post>
      </pgc>
    </titles>
  </titleset>
</dvdauthor>
EOF

# Replace placeholders with actual paths
sed -i "s|/tmp/dvd_structure|$DVD_SOURCE|g" "$WORK_DIR/dvd.xml"
sed -i "s|/tmp/dvd_work|$WORK_DIR|g" "$WORK_DIR/dvd.xml"

# Build DVD structure
echo "Building DVD structure..."
dvdauthor -o "$DVD_SOURCE" -x "$WORK_DIR/dvd.xml" > /dev/null 2>&1

if [ ! -d "$DVD_SOURCE/VIDEO_TS" ]; then
    echo "ERROR: DVD structure creation failed"
    exit 1
fi

# Create ISO from DVD structure
echo "Creating DVD ISO..."
genisoimage -dvd-video -udf -o "$ISO_PATH" "$DVD_SOURCE" > /dev/null 2>&1

if [ ! -f "$ISO_PATH" ]; then
    echo "ERROR: ISO creation failed"
    exit 1
fi

# Set permissions
chown ga:ga "$ISO_PATH"
chmod 644 "$ISO_PATH"

# Clean up temporary files
rm -rf "$DVD_SOURCE" "$WORK_DIR"

echo "✅ DVD ISO created: $ISO_PATH"
ls -lh "$ISO_PATH"

# Configure VLC for DVD playback
VLC_CONFIG="/home/ga/.config/vlc/vlcrc"
mkdir -p "$(dirname $VLC_CONFIG)"

# Ensure DVD navigation mode is enabled
if [ -f "$VLC_CONFIG" ]; then
    # Remove old DVD settings
    sed -i '/^dvd-device=/d' "$VLC_CONFIG"
    sed -i '/^dvdnav-menu=/d' "$VLC_CONFIG"
fi

cat >> "$VLC_CONFIG" <<EOF

# DVD settings for navigation task
dvdnav-menu=1
dvd-device=$ISO_PATH
EOF

chown -R ga:ga /home/ga/.config/vlc

# Launch VLC with RC interface
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --extraintf rc --rc-host localhost:9999 > /tmp/vlc_dvd_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_dvd_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Wait for RC interface
echo "Waiting for RC interface..."
for i in {1..10}; do
    if echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
        echo "RC interface ready"
        break
    fi
    sleep 1
done

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 2

echo "=== DVD Bonus Features Navigation Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Load DVD ISO: $ISO_PATH"
echo "  2. Use Media → Open Disc or Media → Open File"
echo "  3. Navigate to Title 2 (Bonus Features)"
echo "  4. Methods:"
echo "     - Playback → Title menu"
echo "     - Press 'T' key to cycle titles"
echo "     - Right-click → Playback → Title → Title 2"
echo "  5. Ensure Title 2 is playing (NOT Title 1 - main feature)"
echo ""
echo "⚠️  Title 1 = Main Feature (wrong)"
echo "✅  Title 2 = Bonus Features (correct)"