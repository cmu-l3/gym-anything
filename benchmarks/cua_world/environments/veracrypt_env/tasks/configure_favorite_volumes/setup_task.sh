#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Favorite Volumes Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define volume paths
VOL_DIR="/home/ga/Volumes"
mkdir -p "$VOL_DIR"

# Function to create a volume if it doesn't exist
create_vol() {
    local name=$1
    local pass=$2
    local size=$3
    
    if [ ! -f "$VOL_DIR/$name" ]; then
        echo "Creating $name..."
        veracrypt --text --create "$VOL_DIR/$name" \
            --size="$size" \
            --password="$pass" \
            --encryption=AES \
            --hash=SHA-512 \
            --filesystem=FAT \
            --pim=0 \
            --keyfiles='' \
            --random-source=/dev/urandom \
            --non-interactive
            
        # Add some dummy data to make it realistic
        echo "Populating $name..."
        mkdir -p /tmp/vc_setup_mnt
        veracrypt --text --mount "$VOL_DIR/$name" /tmp/vc_setup_mnt \
            --password="$pass" --pim=0 --keyfiles='' --protect-hidden=no --non-interactive
            
        echo "Confidential Project Data $(date)" > "/tmp/vc_setup_mnt/README.txt"
        
        veracrypt --text --dismount /tmp/vc_setup_mnt --non-interactive
        rmdir /tmp/vc_setup_mnt
    else
        echo "$name already exists."
    fi
}

# Create the 3 specific volumes
create_vol "project_active.hc" "Project2024!" "15M"
create_vol "reference_docs.hc" "RefDocs2024!" "10M"
create_vol "archive_cold.hc" "Archive2024!" "10M"

# Clear any existing configuration to ensure clean slate
rm -f /home/ga/.config/VeraCrypt/Configuration.xml
rm -f /home/ga/.VeraCrypt/Configuration.xml

# Fix permissions
chown -R ga:ga "$VOL_DIR"
chown -R ga:ga /home/ga/.config 2>/dev/null || true
chown -R ga:ga /home/ga/.VeraCrypt 2>/dev/null || true

# Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Maximize window
WID=$(get_veracrypt_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="