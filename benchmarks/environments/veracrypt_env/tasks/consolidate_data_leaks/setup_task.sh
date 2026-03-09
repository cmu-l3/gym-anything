#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Consolidate Data Leaks Task ==="

# 1. Clean up any previous runs
rm -f /home/ga/Volumes/legal_vault.hc 2>/dev/null || true
rm -f /home/ga/Desktop/draft_nda.txt 2>/dev/null || true
rm -f /home/ga/Documents/SF312_Copy.txt 2>/dev/null || true
rm -f /home/ga/Downloads/agreement_scan.txt 2>/dev/null || true
rm -f /home/ga/Desktop/shopping_list.txt 2>/dev/null || true
rm -f /home/ga/Documents/meeting_notes.txt 2>/dev/null || true

# 2. Create the encrypted volume
echo "Creating encrypted volume..."
veracrypt --text --create /home/ga/Volumes/legal_vault.hc \
    --size=10M \
    --password='Compliance2024!' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 3. Create Leak Files (Sensitive)
# Using the asset file as source, or creating if missing
SOURCE_FILE="/workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt"
if [ ! -f "$SOURCE_FILE" ]; then
    echo "Creating dummy source file..."
    mkdir -p /workspace/assets/sample_data
    echo "CLASSIFIED INFORMATION NONDISCLOSURE AGREEMENT" > "$SOURCE_FILE"
    echo "An agreement between (Name) and the United States." >> "$SOURCE_FILE"
fi

echo "Scattering sensitive files..."
cp "$SOURCE_FILE" /home/ga/Desktop/draft_nda.txt
cp "$SOURCE_FILE" /home/ga/Documents/SF312_Copy.txt
cp "$SOURCE_FILE" /home/ga/Downloads/agreement_scan.txt

# 4. Create Distractor Files (Non-sensitive)
echo "Creating distractor files..."
echo "Milk, Eggs, Bread, Butter" > /home/ga/Desktop/shopping_list.txt
echo "Meeting at 10 AM. Topic: Q3 Budget." > /home/ga/Documents/meeting_notes.txt

# 5. Record initial state
date +%s > /tmp/task_start_time.txt
# Calculate MD5 of the sensitive content to verify integrity later
md5sum "$SOURCE_FILE" | awk '{print $1}' > /tmp/sensitive_hash.txt

# 6. Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Focus VeraCrypt window
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize for visibility
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="