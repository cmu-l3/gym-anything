#!/bin/bash
echo "=== Setting up fix_failed_post task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MongoDB is running
echo "Ensuring MongoDB is running..."
systemctl start mongod 2>/dev/null || true
sleep 3

# 1. Create the backup asset and directory
echo "Creating backup assets..."
mkdir -p /home/ga/Documents/CampaignAssets

# Try to download a real CC0 image for realistic data, fallback to ImageMagick generation
if ! curl -L -s -o /home/ga/Documents/CampaignAssets/summer_sale_promo.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e0/JPEG_example_JPG_RIP_050.jpg/500px-JPEG_example_JPG_RIP_050.jpg"; then
    convert -size 800x600 plasma:fractal /home/ga/Documents/CampaignAssets/summer_sale_promo.jpg
fi
chown -R ga:ga /home/ga/Documents/CampaignAssets

# 2. Ensure target directory exists but the file is MISSING (simulating the accidental deletion)
TARGET_DIR="/opt/socioboard/socioboard-api/publish/public/media"
mkdir -p "$TARGET_DIR"
rm -f "$TARGET_DIR/summer_sale_promo.jpg"
chown -R ga:ga /opt/socioboard/socioboard-api/publish/public/media 2>/dev/null || true

# 3. Setup MongoDB Document
echo "Configuring failed post in MongoDB..."
MONGO_CMD=""
if command -v mongosh >/dev/null 2>&1; then
  MONGO_CMD="mongosh"
else
  MONGO_CMD="mongo"
fi

$MONGO_CMD socioboard --quiet --eval '
  db.scheduled_informations.deleteOne({schedule_id: "summer_sale_123"});
  db.scheduled_informations.insertOne({
      schedule_id: "summer_sale_123",
      postType: "Image",
      description: "Huge Summer Sale! Get 50% off all items.",
      mediaUrl: "summer_sale_promo.jpg",
      status: 6,
      errorMessage: "Error: ENOENT: no such file or directory, stat \x27/opt/socioboard/socioboard-api/publish/public/media/summer_sale_promo.jpg\x27",
      createdDate: new Date()
  });
' > /dev/null 2>&1

# 4. Take initial screenshot (Terminal or Desktop)
# Open a terminal for the agent to use
su - ga -c "DISPLAY=:1 gnome-terminal --maximize" &
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="