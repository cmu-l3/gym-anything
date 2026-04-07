#!/bin/bash
# Setup script for steganography_eof_triage task

echo "=== Setting up steganography_eof_triage task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean up stale files
rm -f /tmp/steg_result.json 2>/dev/null || true
for d in /home/ga/Cases/Steganography_Triage_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done
rm -rf /home/ga/Reports/extracted_jpegs 2>/dev/null || true
mkdir -p /home/ga/Reports/extracted_jpegs
chown -R ga:ga /home/ga/Reports 2>/dev/null || true

# Verify disk image exists
IMAGE="/home/ga/evidence/jpeg_search.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi

# ==============================================================================
# Inject Authentic Steganography Data into the Forensic Image
# We generate valid JPEGs with appended data and insert them via mcopy
# ==============================================================================
echo "Injecting steganography artifacts into the disk image..."
python3 -c "
import binascii

# Minimal 1x1 valid JPEG hex string
jpeg_hex = 'ffd8ffe000104a46494600010101004800480000ffdb004300080606070605080707070909080a0c140d0c0b0b0c1912130f141d1a1f1e1d1a1c1c20242e2720222c231c1c2837292c30313434341f27393d38323c2e333432ffdb0043010909090c0b0c180d0d1832211c213232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232ffc00011080001000103012200021101031101ffc4001f0000010501010101010100000000000000000102030405060708090a0bffc400b5100002010303020403050504040000017d01020300041105122131410613516107227114328191a1082342b1c11552d1f02433627282090a161718191a25262728292a3435363738393a434445464748494a535455565758595a636465666768696a737475767778797a838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9faffc4001c01000203010101010000000000000000000001020304050607080bffc400821100020102040403040705040400010277000102031104052131061241510761711322328108144291a1b1c109233352f0156272d10a162434e125f11718191a262728292a35363738393a434445464748494a535455565758595a636465666768696a737475767778797a82838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae2e3e4e5e6e7e8e9eaf2f3f4f5f6f7f8f9faffda000c03010002110311003f00f074a28a28a003ffd9'
base = binascii.unhexlify(jpeg_hex)

with open('/tmp/normal_photo.jpg', 'wb') as f: 
    f.write(base)
    
with open('/tmp/secret_photo_1.jpg', 'wb') as f: 
    f.write(base + b'SUSPICIOUS_APPENDED_DATA_BLOCK_A_192837465')

with open('/tmp/secret_photo_2.jpg', 'wb') as f: 
    f.write(base + b'ENCRYPTED_ZIP_ARCHIVE_HEADER_PK\x03\x04\x00\x00\x00')
"

# Inject into the FAT evidence image using mtools
mcopy -i "$IMAGE" /tmp/normal_photo.jpg ::/normal_photo.jpg 2>/dev/null || true
mcopy -i "$IMAGE" /tmp/secret_photo_1.jpg ::/secret_photo_1.jpg 2>/dev/null || true
mcopy -i "$IMAGE" /tmp/secret_photo_2.jpg ::/secret_photo_2.jpg 2>/dev/null || true
echo "Steganography artifacts injected successfully."

# ==============================================================================
# Launch Autopsy GUI
# ==============================================================================
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy Welcome screen..."
wait_for_autopsy_window 300

# Ensure the window is fully up and try to maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen is visible."
        break
    fi
    sleep 2
done

# Dismiss any stray dialogs and maximize main window
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "autopsy" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot showing Autopsy ready for action
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="