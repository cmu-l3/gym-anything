#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Backup VLC Preferences Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure VLC config directory exists
VLC_CONFIG_DIR="/home/ga/.config/vlc"
mkdir -p "$VLC_CONFIG_DIR"

# Create a distinctive custom VLC configuration that needs to be backed up
echo "Creating custom VLC configuration..."

cat > "$VLC_CONFIG_DIR/vlcrc" << 'EOF'
# VLC preferences - Custom configuration for backup task
# This config has been customized by the user over months of use

[qt]
qt-privacy-ask=0
qt-minimal-view=1
qt-system-tray=1
qt-start-minimized=0
qt-notification=1
qt-updates-notif=0

[core]
# Custom playback settings
loop=1
repeat=0
volume=180
audio-time-stretch=1
video-on-top=1
play-and-exit=0

# Custom hotkeys (user's preferred shortcuts)
key-play-pause=Space
key-faster=f
key-slower=s
key-jump+short=Right
key-jump-short=Left
key-vol-up=Ctrl+Up
key-vol-down=Ctrl+Down
key-next=n
key-prev=p
key-quit=Ctrl+q
key-fullscreen=F11

# Custom directories
snapshot-path=/home/ga/Pictures/vlc/snapshots
open-path=/home/ga/Videos

[video]
# Video preferences
video-title-show=0
snapshot-format=png
snapshot-preview=1
video-filter=
vout=

[audio]
# Custom audio settings (for user's hearing profile)
audio-visual=spectrometer
norm-max-level=2.0
audio-replay-gain-mode=track
audio-replay-gain-preamp=0.0
audio-replay-gain-default=-7.0

[subtitle]
# Subtitle preferences
subtitle-autodetect-fuzzy=3
sub-language=eng
subsdec-encoding=UTF-8

[playlist]
# Playlist behavior
playlist-autostart=1
play-and-stop=0
EOF

# Create VLC Qt interface config with UI customizations
cat > "$VLC_CONFIG_DIR/vlc-qt-interface.conf" << 'EOF'
[General]
filedialog-path=/home/ga/Videos
geometry=@ByteArray(\x1\xd9\xd0\xcb\0\x3\0\0\0\0\0\0\0\0\0\x1e\0\0\x5U\0\0\x2\xff\0\0\0\0\0\0\0\x1e\0\0\x5U\0\0\x2\xff\0\0\0\0\0\0\0\0\a\x80\0\0\0\0\0\0\0\x1e\0\0\x5U\0\0\x2\xff)

[MainWindow]
pl-dock-status=true
playlist-visible=true
adv-controls=1
status-bar-visible=true
bgSize=@Size(1366 768)
playlistSize=@Size(600 400)

[RecentsMRL]
list=file:///home/ga/Videos/sample_video.mp4, file:///home/ga/Music/sample_audio.mp3, file:///home/ga/Videos/color_test.mp4
times=0, 45000, 12000

[Preferences]
geometry=@ByteArray(\x1\xd9\xd0\xcb\0\x3\0\0\0\0\x1\x90\0\0\0\xa0\0\0\x5\xef\0\0\x3\x7f\0\0\x1\x90\0\0\0\xa0\0\0\x5\xef\0\0\x3\x7f\0\0\0\0\0\0\0\0\a\x80\0\0\x1\x90\0\0\0\xa0\0\0\x5\xef\0\0\x3\x7f)
EOF

# Set proper ownership
chown -R ga:ga "$VLC_CONFIG_DIR"

# Ensure backup directory exists but is EMPTY (user needs to create backup)
BACKUP_DIR="/home/ga/Documents/vlc_backup"
rm -rf "$BACKUP_DIR"
mkdir -p "/home/ga/Documents"
chown ga:ga "/home/ga/Documents"

echo "✅ Custom VLC configuration created"
echo "📁 Config location: $VLC_CONFIG_DIR"
echo "📁 Expected backup location: $BACKUP_DIR"

# Launch VLC (optional - gives agent context that VLC exists and is configured)
echo "Launching VLC to demonstrate configured state..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_backup_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "WARNING: VLC failed to start (non-critical for this task)"
else
    if wait_for_window "VLC media player" 20; then
        # Click on center of the screen to select current desktop
        echo "Selecting desktop..."
        su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
        sleep 1
        
        # Focus window
        wid=$(get_vlc_window_id)
        if [ -n "$wid" ]; then
            focus_window "$wid"
        fi
        echo "✅ VLC launched successfully"
    fi
fi

echo ""
echo "=== Backup VLC Preferences Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  You've customized VLC over months:"
echo "  - Custom hotkeys for your workflow"
echo "  - Audio filters for your hearing profile"
echo "  - Interface tweaks and default directories"
echo "  - Specific playback behaviors"
echo ""
echo "  You're getting a new computer tomorrow and need to backup"
echo "  these settings so you can restore them on the new machine."
echo ""
echo "📝 TASK:"
echo "  Backup VLC preferences to: ~/Documents/vlc_backup/"
echo ""
echo "💡 HINTS:"
echo "  - VLC stores config in: ~/.config/vlc/"
echo "  - Essential files: vlcrc, vlc-qt-interface.conf"
echo "  - Can use file manager (show hidden files with Ctrl+H)"
echo "  - Or use terminal: cp ~/.config/vlc/vlcrc ~/Documents/vlc_backup/"
echo ""