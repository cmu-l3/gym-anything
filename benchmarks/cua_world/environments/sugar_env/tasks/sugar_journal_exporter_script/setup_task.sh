#!/bin/bash
echo "=== Setting up sugar_journal_exporter_script task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task start timestamp
date +%s > /tmp/journal_exporter_start_ts
chmod 666 /tmp/journal_exporter_start_ts

# Clean up any existing script or output
rm -f /home/ga/Documents/journal_exporter.py 2>/dev/null || true
rm -rf /home/ga/Documents/Exported_Logs 2>/dev/null || true

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Inject test data into the datastore
echo "Injecting test data into datastore..."
su - ga -c "python3 << 'EOF'
import os
import uuid
import time
import shutil

datastore_path = '/home/ga/.sugar/default/datastore'
os.makedirs(datastore_path, exist_ok=True)

# Delete existing entries to ensure a clean state for the test
for item in os.listdir(datastore_path):
    item_path = os.path.join(datastore_path, item)
    if os.path.isdir(item_path):
        try:
            shutil.rmtree(item_path)
        except Exception as e:
            pass

alice_text = '''Alice was beginning to get very tired of sitting by her sister on the bank,
and of having nothing to do: once or twice she had peeped into the
book her sister was reading, but it had no pictures or conversations
in it...'''

files_to_create = [
    {'title': 'Reading Log Chapter 1', 'mime': 'text/plain', 'data': alice_text, 'type': 'text'},
    {'title': 'Reading Log Chapter 2', 'mime': 'text/plain', 'data': 'The pool of tears...', 'type': 'text'},
    {'title': 'Reading Log Chapter 3', 'mime': 'text/plain', 'data': 'A caucus-race and a long tale...', 'type': 'text'},
    {'title': 'White Rabbit Drawing', 'mime': 'image/png', 'data': '', 'type': 'image'}
]

for idx, f_info in enumerate(files_to_create):
    uid = str(uuid.uuid4())
    entry_dir = os.path.join(datastore_path, uid)
    meta_dir = os.path.join(entry_dir, 'metadata')
    os.makedirs(meta_dir, exist_ok=True)
    
    # Write metadata
    with open(os.path.join(meta_dir, 'title'), 'w') as f:
        f.write(f_info['title'])
    with open(os.path.join(meta_dir, 'mime_type'), 'w') as f:
        f.write(f_info['mime'])
    with open(os.path.join(meta_dir, 'timestamp'), 'w') as f:
        f.write(str(int(time.time()) - 1000 + idx))
        
    # Write data
    data_path = os.path.join(entry_dir, 'data')
    if f_info['type'] == 'text':
        with open(data_path, 'w') as f:
            f.write(f_info['data'])
    else:
        # Create a dummy PNG file
        with open(data_path, 'wb') as f:
            f.write(b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89')
EOF"

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/journal_exporter_start.png" 2>/dev/null || true

echo "=== setup complete ==="