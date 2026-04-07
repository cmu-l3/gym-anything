#!/bin/bash
echo "=== Setting up migrate_media_urls_mongodb task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure MongoDB is running
if ! systemctl is-active --quiet mongod; then
    echo "Starting MongoDB..."
    systemctl start mongod
    sleep 3
fi

# Wait for MongoDB to be ready
for i in {1..30}; do
    if mongosh --quiet --eval "db.runCommand({ping: 1})" 2>/dev/null; then
        echo "MongoDB is ready."
        break
    fi
    sleep 1
done

# Prepare realistic MongoDB documents with complex structures to avoid trivial replacements
cat > /tmp/seed_posts.json << 'EOF'
{"postId": 1001, "postType": "Image", "description": "Summer sale starts now!", "mediaUrl": "http://media.acmesocial.legacy/campaigns/summer/sale_banner_v2.jpg", "ownerId": 1, "teamId": 1, "status": 1, "createdDate": "2024-06-01T10:00:00Z"}
{"postId": 1002, "postType": "Image", "description": "New arrivals in store.", "mediaUrl": "http://media.acmesocial.legacy/products/shoes/sneaker_red.png", "ownerId": 1, "teamId": 1, "status": 1, "createdDate": "2024-06-02T11:15:00Z"}
{"postId": 1003, "postType": "Video", "description": "Watch our brand documentary.", "mediaUrl": "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "ownerId": 2, "teamId": 1, "status": 1, "createdDate": "2024-06-03T14:20:00Z"}
{"postId": 1004, "postType": "Image", "description": "Flash sale for 24 hours only.", "mediaUrl": "http://media.acmesocial.legacy/promos/flash/24hr_timer.gif", "ownerId": 1, "teamId": 2, "status": 1, "createdDate": "2024-06-04T09:00:00Z"}
{"postId": 1005, "postType": "Link", "description": "Read our latest blog post on industry trends.", "mediaUrl": "https://imgur.com/gallery/industry_trends", "ownerId": 3, "teamId": 1, "status": 1, "createdDate": "2024-06-05T16:45:00Z"}
EOF

cat > /tmp/seed_drafts.json << 'EOF'
{"draftId": 2001, "postType": "Image", "description": "Draft: Autumn collection sneak peek", "mediaUrl": "http://media.acmesocial.legacy/campaigns/autumn/preview_01.jpg", "ownerId": 1, "teamId": 1, "status": 0, "createdDate": "2024-08-01T10:00:00Z"}
{"draftId": 2002, "postType": "Video", "description": "Draft: CEO Interview snippets", "mediaUrl": "https://vimeo.com/123456789", "ownerId": 2, "teamId": 1, "status": 0, "createdDate": "2024-08-02T11:00:00Z"}
{"draftId": 2003, "postType": "Image", "description": "Draft: Halloween special offers", "mediaUrl": "http://media.acmesocial.legacy/seasonal/halloween/spooky_sale.png", "ownerId": 1, "teamId": 2, "status": 0, "createdDate": "2024-08-03T09:30:00Z"}
EOF

# Import data into MongoDB (drop existing to ensure clean state)
echo "Seeding databases..."
mongosh socioboard --quiet --eval "db.userpublishposts.drop(); db.drafts.drop();"
mongoimport --db socioboard --collection userpublishposts --file /tmp/seed_posts.json --type json --quiet
mongoimport --db socioboard --collection drafts --file /tmp/seed_drafts.json --type json --quiet

# Record initial state
cat > /tmp/initial_state.json << 'EOF'
{
  "legacy_count_posts": 3,
  "legacy_count_drafts": 2,
  "control_count_posts": 2,
  "control_count_drafts": 1,
  "total_legacy": 5,
  "total_control": 3
}
EOF

# Clean up temp files
rm /tmp/seed_posts.json /tmp/seed_drafts.json

# Open a terminal for the agent since this is a CLI/DB task
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize" &
    sleep 3
fi

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="