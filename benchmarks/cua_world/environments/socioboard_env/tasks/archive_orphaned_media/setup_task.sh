#!/bin/bash
echo "=== Setting up archive_orphaned_media task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for MongoDB to be responsive
echo "Waiting for MongoDB..."
for i in {1..30}; do
    if mongosh --quiet --eval "db.adminCommand('ping')" 2>/dev/null; then
        break
    fi
    sleep 1
done

# Setup directories
SRC_DIR="/opt/socioboard/socioboard-api/publish/media_uploads"
mkdir -p "$SRC_DIR"
rm -f "$SRC_DIR"/* 2>/dev/null || true

# Clear target collection to ensure a clean state
mongosh socioboard --quiet --eval "db.user_media.deleteMany({})" 2>/dev/null || true

# Generate realistic dummy data and database records
cat > /tmp/setup_media_data.py << 'EOF'
import os
import json
import random
import string
import subprocess

src_dir = "/opt/socioboard/socioboard-api/publish/media_uploads"
gt_file = "/var/backups/.sb_media_state.json"

def random_name(ext=".jpg"):
    return "sb_media_" + ''.join(random.choices(string.ascii_lowercase + string.digits, k=10)) + ext

# Generate active and orphan datasets
active_files = [random_name(random.choice([".jpg", ".png", ".webp"])) for _ in range(25)]
orphan_files = [random_name(random.choice([".jpg", ".png", ".gif"])) for _ in range(12)]

# Use Imagemagick to create valid physical image files
colors = ["red", "blue", "green", "yellow", "purple", "gray", "orange", "teal"]
for f in active_files + orphan_files:
    path = os.path.join(src_dir, f)
    color = random.choice(colors)
    subprocess.run(["convert", "-size", "400x400", f"canvas:{color}", path], check=False)

# Save ground truth to a hidden location
with open(gt_file, 'w') as out:
    json.dump({"active_files": active_files, "orphan_files": orphan_files}, out)

# Generate MongoDB JS insertion script
mongo_script = "use socioboard;\n"
for f in active_files:
    # Insert with some realistic auxiliary data
    mongo_script += f"db.user_media.insertOne({{file_name: '{f}', status: 'active', size: 1204, uploader: 'user1'}});\n"

with open('/tmp/insert_mongo.js', 'w') as f:
    f.write(mongo_script)
EOF

# Run python script and mongo insertion
python3 /tmp/setup_media_data.py
mongosh < /tmp/insert_mongo.js > /dev/null

# Clean up scripts
rm /tmp/setup_media_data.py /tmp/insert_mongo.js

# Set correct permissions
chown -R ga:ga "$SRC_DIR"
chmod 700 /var/backups/.sb_media_state.json

# Clean any existing outputs
rm -rf /home/ga/archive_orphaned 2>/dev/null || true
rm -f /home/ga/orphan_report.txt 2>/dev/null || true

# Launch terminal for the agent to use
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
sleep 2

# Take initial screenshot showing terminal ready
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="