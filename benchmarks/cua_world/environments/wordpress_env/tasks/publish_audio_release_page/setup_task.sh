#!/bin/bash
# Setup script for publish_audio_release_page task
# Prepares media files and records initial state

echo "=== Setting up publish_audio_release_page task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp (for detecting newly uploaded media)
date +%s | sudo tee /tmp/task_start_timestamp > /dev/null
sudo chmod 666 /tmp/task_start_timestamp

# ============================================================
# Prepare Media Assets
# ============================================================
MUSIC_DIR="/home/ga/Music/Classical_EP"
mkdir -p "$MUSIC_DIR"

echo "Downloading media assets..."
# Use CC0 / Public Domain assets from stable sources
curl -sL -A "Mozilla/5.0" "https://upload.wikimedia.org/wikipedia/commons/e/ea/Frederic_Chopin_-_Fantaisie_-_Impromptu_in_C_sharp_minor%2C_Op._66.mp3" -o "$MUSIC_DIR/track1_chopin.mp3"
curl -sL -A "Mozilla/5.0" "https://upload.wikimedia.org/wikipedia/commons/0/07/Gymnopedie_No._1.mp3" -o "$MUSIC_DIR/track2_satie.mp3"
curl -sL -A "Mozilla/5.0" "https://upload.wikimedia.org/wikipedia/commons/6/64/Claude_Debussy_-_Clair_de_lune.mp3" -o "$MUSIC_DIR/track3_debussy.mp3"
curl -sL -A "Mozilla/5.0" "https://picsum.photos/id/145/800/800.jpg" -o "$MUSIC_DIR/album_cover.jpg"

# Create Track Notes document
cat > "$MUSIC_DIR/ep_assets.txt" << 'EOF'
Track 1 - Chopin
Composed in 1834 and published posthumously, the Fantaisie-Impromptu is one of Chopin's most recognized and frequently performed piano compositions.

Track 2 - Satie
Published in Paris starting in 1888, the Gymnopédies are atmospheric, delicate piano works that anticipated the ambient music movement.

Track 3 - Debussy
The third and most famous movement of the Suite bergamasque, Clair de lune, takes its title from Paul Verlaine's beautiful poem of the same name.
EOF

# Ensure proper permissions for the agent
chown -R ga:ga /home/ga/Music
chmod -R 755 /home/ga/Music

# ============================================================
# Clean Up Previous Runs
# ============================================================
cd /var/www/html/wordpress
# Delete any existing page with this title to ensure a clean slate
EXISTING_ID=$(wp post list --post_type=page --title="Classical Sessions EP" --field=ID --allow-root 2>/dev/null || echo "")
if [ -n "$EXISTING_ID" ]; then
    wp post delete "$EXISTING_ID" --force --allow-root 2>/dev/null || true
fi

# ============================================================
# Ensure Firefox is Running
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="