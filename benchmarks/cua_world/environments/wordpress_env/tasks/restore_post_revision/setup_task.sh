#!/bin/bash
# Setup script for restore_post_revision task
# Creates a post, updates it to generate good revisions, then corrupts it.

echo "=== Setting up restore_post_revision task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
TASK_START=$(date +%s)
echo "$TASK_START" | sudo tee /tmp/task_start_time > /dev/null
sudo chmod 666 /tmp/task_start_time

cd /var/www/html/wordpress

# ============================================================
# Create Version 1 (The Good Original)
# ============================================================
echo "Creating original good post..."
V1_CONTENT="<!-- wp:heading --><h2>Executive Summary</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p>This year focuses heavily on brand awareness and improving overall customer retention by 15%.</p><!-- /wp:paragraph -->
<!-- wp:heading --><h2>Q1 Objectives</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p>Launch the new customer loyalty program and host regional events in Boston, Chicago, and Denver.</p><!-- /wp:paragraph -->
<!-- wp:heading --><h2>Q2 Goals</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p>Expand international market presence with new campaigns targeting Southeast Asia, Eastern Europe, and South America.</p><!-- /wp:paragraph -->
<!-- wp:heading --><h2>Budget Allocation</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p>Total marketing spend is capped at $2.4 million, with 40% allocated to digital channels.</p><!-- /wp:paragraph -->"

POST_ID=$(wp post create --post_type=post --post_title="Annual Marketing Strategy Report" --post_content="$V1_CONTENT" --post_status=publish --porcelain --allow-root 2>/dev/null)

if [ -z "$POST_ID" ]; then
    echo "ERROR: Failed to create post."
    exit 1
fi
echo "Post created with ID: $POST_ID"

# Wait to ensure distinct timestamps for revisions
sleep 2

# ============================================================
# Create Version 2 (Minor Update - still Good)
# ============================================================
echo "Creating minor revision..."
V2_CONTENT="${V1_CONTENT}
<!-- wp:paragraph -->
<p><em>Note: Strategy review meeting scheduled for March 15. All department leads please confirm attendance.</em></p>
<!-- /wp:paragraph -->"

wp post update "$POST_ID" --post_content="$V2_CONTENT" --allow-root > /dev/null
sleep 2

# ============================================================
# Create Version 3 (Corrupted - Current State)
# ============================================================
echo "Corrupting the post content..."
V3_CONTENT="<!-- wp:heading --><h2>Executive Summary</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p>This year focuses heavily on brand awareness and improving overall customer retention by 15%.</p><!-- /wp:paragraph -->
<!-- wp:heading --><h2>Q1 Objectives</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p>Launch the new customer loyalty program and host regional events in Boston, Chicago, and Denver.</p><!-- /wp:paragraph -->
<!-- wp:heading --><h2>Q2 Goals</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p><strong>[DRAFT NOTES - NEED TO REWRITE THIS ENTIRE SECTION. Lost the region list.]</strong></p><!-- /wp:paragraph -->
<!-- wp:heading --><h2>Budget Allocation</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p><strong>[TODO: get updated numbers from finance team. placeholder budget goes here]</strong></p><!-- /wp:paragraph -->"

wp post update "$POST_ID" --post_content="$V3_CONTENT" --allow-root > /dev/null

# Get initial revision count
REV_COUNT=$(wp post list --post_type=revision --post_parent="$POST_ID" --format=count --allow-root 2>/dev/null || echo "0")
echo "Initial revision count: $REV_COUNT"

# Save baseline state
cat > /tmp/post_baseline.json << BASEEOF
{
    "post_id": $POST_ID,
    "initial_revision_count": $REV_COUNT,
    "task_start_time": $TASK_START
}
BASEEOF
chmod 666 /tmp/post_baseline.json

# ============================================================
# Ensure Firefox is running
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8
fi

# Focus Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent should navigate to post ID $POST_ID, use Revisions, and restore the content."