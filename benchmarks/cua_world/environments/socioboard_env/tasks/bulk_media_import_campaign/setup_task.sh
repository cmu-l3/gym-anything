#!/bin/bash
echo "=== Setting up bulk_media_import_campaign task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
sudo rm -f /tmp/task_start_timestamp /tmp/task_start.png /tmp/initial_media_count /tmp/task_result.json 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Clean up any existing task files
rm -rf /home/ga/Documents/Processed_Campaign
rm -f /home/ga/Documents/summer_campaign_raw.zip
rm -rf /home/ga/Documents/raw_images

# Download real photographic images from picsum.photos to simulate campaign assets
log "Downloading real high-resolution stock photos..."
mkdir -p /home/ga/Documents/raw_images
cd /home/ga/Documents/raw_images

# Fetch 10 random 2560x1440 images
for i in {1..10}; do
    # picsum.photos provides real, CC0 public domain photography
    wget -q -O "summer_camp_asset_${i}.jpg" "https://picsum.photos/2560/1440?random=${i}"
    # Small sleep to avoid rate limiting
    sleep 0.5
done

# Zip them up into the expected archive
log "Creating the campaign raw archive..."
zip -q /home/ga/Documents/summer_campaign_raw.zip *.jpg
cd /home/ga
rm -rf /home/ga/Documents/raw_images

# Ensure correct permissions
chown ga:ga /home/ga/Documents/summer_campaign_raw.zip

# Record initial MongoDB media count (Socioboard 4.0 stores user media in Mongo)
log "Recording baseline Socioboard media count..."
python3 << 'PYEOF'
import sys
try:
    from pymongo import MongoClient
    client = MongoClient("mongodb://localhost:27017/", serverSelectionTimeoutMS=2000)
    db = client.socioboard
    
    count = 0
    # Different versions/configurations of SB 4.0 use different collection names
    for coll_name in ["user_medias", "user_media", "media_informations"]:
        if coll_name in db.list_collection_names():
            count += db[coll_name].count_documents({})
    
    with open('/tmp/initial_media_count', 'w') as f:
        f.write(str(count))
    print(f"Initial media count: {count}")
except Exception as e:
    print(f"Failed to connect to MongoDB: {e}")
    with open('/tmp/initial_media_count', 'w') as f:
        f.write("0")
PYEOF

# Ensure Socioboard is running
if ! wait_for_http "http://localhost/" 120; then
  echo "ERROR: Socioboard not reachable at http://localhost/"
fi

# Clear session and load login page
open_socioboard_page "http://localhost/logout"
sleep 2
navigate_to "http://localhost/login"
sleep 3

# Take initial screenshot showing the environment is ready
take_screenshot /tmp/task_start.png
log "Task start screenshot saved."
echo "=== Task setup complete ==="