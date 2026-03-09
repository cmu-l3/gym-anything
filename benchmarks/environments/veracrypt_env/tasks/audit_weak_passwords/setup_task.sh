#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Audit Weak Passwords Task ==="

# Record start time
date +%s > /tmp/task_start_time.txt

# Create Documents directory if not exists
mkdir -p /home/ga/Documents

# 1. Create the Weak Password Dictionary
echo "Creating password dictionary..."
cat > /home/ga/Documents/weak_passwords.txt << EOF
123456
password
12345678
qwerty
12345
123456789
football
skywalker
princess
monkey
EOF
chown ga:ga /home/ga/Documents/weak_passwords.txt

# 2. Create Encrypted Volumes
# We create small containers to save time. 
# Using --pim=0 (default) and no keyfiles to keep it simple for the dictionary attack.

VOL_DIR="/home/ga/Volumes"
mkdir -p "$VOL_DIR"

# Clean up any existing volumes
rm -f "$VOL_DIR"/archive_*.hc

echo "Creating Volume A (Strong Password)..."
veracrypt --text --create "$VOL_DIR/archive_alpha.hc" \
    --size=2M \
    --password='Xk9#m2$vLp' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

echo "Creating Volume B (Weak Password: princess)..."
veracrypt --text --create "$VOL_DIR/archive_bravo.hc" \
    --size=2M \
    --password='princess' \
    --encryption=Serpent \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

echo "Creating Volume C (Strong Password)..."
veracrypt --text --create "$VOL_DIR/archive_charlie.hc" \
    --size=2M \
    --password='7d!Qz@1M4' \
    --encryption=Twofish \
    --hash=Whirlpool \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# Fix permissions
chown -R ga:ga "$VOL_DIR"

# 3. Launch VeraCrypt GUI
echo "Starting VeraCrypt..."
if ! is_veracrypt_running; then
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

# Ensure window is visible
if ! wait_for_window "VeraCrypt" 20; then
    echo "WARNING: VeraCrypt window not found"
fi

# Maximize and focus
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Ensure it's not minimized
    DISPLAY=:1 wmctrl -i -r "$wid" -b remove,hidden,shaded 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="