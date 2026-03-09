#!/bin/bash
# Setup script for audit_reorganize_content task (pre_task hook)
# Creates 6 messy posts: 5 legitimate (wrong category, some drafts) + 1 spam.

echo "=== Setting up audit_reorganize_content task ==="

source /workspace/scripts/task_utils.sh

cd /var/www/html/wordpress

# ============================================================
# Clean up posts from previous runs
# ============================================================
for title in "Cloud Computing Trends 2026" "AI in Software Development" \
             "Weekend Hiking Trail Guide" "Healthy Meal Prep Ideas" \
             "Breaking: Local Business Awards Announced" "V1agra Ch3ap Online Buy Now!!!"; do
    OLD_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='$title' AND post_type='post' ORDER BY ID DESC LIMIT 1")
    if [ -n "$OLD_ID" ]; then
        echo "Removing old post '$title' (ID: $OLD_ID)..."
        wp post delete "$OLD_ID" --force --allow-root 2>/dev/null || true
    fi
done

# ============================================================
# Ensure categories exist
# ============================================================
echo "Ensuring categories exist..."
for cat in "Technology" "Lifestyle" "News"; do
    if ! category_exists "$cat"; then
        wp term create category "$cat" --allow-root 2>&1 || true
    fi
done

# Get Uncategorized category ID
UNCAT_ID=$(wp_db_query "SELECT term_id FROM wp_terms WHERE name='Uncategorized' LIMIT 1")
echo "Uncategorized category ID: $UNCAT_ID"

# ============================================================
# Create messy posts (all in Uncategorized, some as drafts)
# ============================================================
echo ""
echo "Creating messy posts..."

# Post 1: Cloud Computing Trends 2026 (DRAFT, should be in Technology)
wp post create --post_type=post --post_status=draft \
    --post_title="Cloud Computing Trends 2026" \
    --post_content="<p>The cloud computing landscape continues to evolve rapidly in 2026. Major trends include the rise of edge computing, serverless architectures gaining mainstream adoption, and multi-cloud strategies becoming the norm for enterprise organizations. Companies are increasingly leveraging AI-powered cloud services for automated scaling and cost optimization. The shift toward sovereign cloud solutions is also accelerating as data privacy regulations tighten globally.</p>" \
    --post_author=1 --allow-root 2>&1
echo "Created 'Cloud Computing Trends 2026' (draft, Uncategorized)"

# Post 2: AI in Software Development (published, should be in Technology)
wp post create --post_type=post --post_status=publish \
    --post_title="AI in Software Development" \
    --post_content="<p>Artificial intelligence is fundamentally transforming how software is built and maintained. Code generation tools powered by large language models are now standard in most development workflows. AI-assisted debugging, automated testing, and intelligent code review are reducing development cycles significantly. However, challenges remain around AI-generated code quality, security vulnerabilities in AI suggestions, and the need for developers to maintain critical thinking skills alongside AI tooling.</p>" \
    --post_author=1 --allow-root 2>&1
echo "Created 'AI in Software Development' (published, Uncategorized)"

# Post 3: Weekend Hiking Trail Guide (published, should be in Lifestyle)
wp post create --post_type=post --post_status=publish \
    --post_title="Weekend Hiking Trail Guide" \
    --post_content="<p>Looking for the perfect weekend hiking adventure? Our comprehensive trail guide covers the best routes for all skill levels. From beginner-friendly nature walks along coastal paths to challenging mountain ascents with stunning summit views, there is something for every outdoor enthusiast. Remember to pack essential supplies including water, snacks, a first-aid kit, and appropriate footwear. Check weather conditions before heading out and always let someone know your planned route.</p>" \
    --post_author=1 --allow-root 2>&1
echo "Created 'Weekend Hiking Trail Guide' (published, Uncategorized)"

# Post 4: Healthy Meal Prep Ideas (published, should be in Lifestyle)
wp post create --post_type=post --post_status=publish \
    --post_title="Healthy Meal Prep Ideas" \
    --post_content="<p>Meal prepping is one of the most effective ways to maintain a healthy diet while saving time and money. Start your week right with these nutritious and delicious meal prep ideas. Focus on balanced macros with lean proteins, complex carbohydrates, and plenty of vegetables. Batch cooking grains like quinoa and brown rice provides a versatile base for multiple meals. Invest in quality storage containers and label everything with preparation dates for food safety.</p>" \
    --post_author=1 --allow-root 2>&1
echo "Created 'Healthy Meal Prep Ideas' (published, Uncategorized)"

# Post 5: Breaking: Local Business Awards (DRAFT, should be in News)
wp post create --post_type=post --post_status=draft \
    --post_title="Breaking: Local Business Awards Announced" \
    --post_content="<p>The annual local business awards ceremony revealed this year's winners across twelve categories. The Best New Business award went to GreenLeaf Sustainable Foods, while TechForward Solutions claimed the Innovation Award for their groundbreaking accessibility platform. Community Impact was awarded to the Downtown Revitalization Project. The ceremony, held at the Convention Center, was attended by over three hundred business leaders and community members celebrating entrepreneurial excellence in our region.</p>" \
    --post_author=1 --allow-root 2>&1
echo "Created 'Breaking: Local Business Awards Announced' (draft, Uncategorized)"

# Post 6: SPAM post (published, should be deleted)
wp post create --post_type=post --post_status=publish \
    --post_title="V1agra Ch3ap Online Buy Now!!!" \
    --post_content="<p>BUY CH3AP P1LLS ONLINE NOW!!! Best pr1ces guaranteed!! V1sit our w3bsite for am4zing d3als on all m3dications. No prescr1ption needed! Fast sh1pping worldwide! Click here now for 90% off!! Limited time offer!!!</p>" \
    --post_author=1 --allow-root 2>&1
echo "Created SPAM post 'V1agra Ch3ap Online Buy Now!!!' (published)"

# ============================================================
# Record baseline
# ============================================================
echo ""
echo "Recording baseline..."

# Get all the post IDs we just created
POST_IDS=""
for title in "Cloud Computing Trends 2026" "AI in Software Development" \
             "Weekend Hiking Trail Guide" "Healthy Meal Prep Ideas" \
             "Breaking: Local Business Awards Announced" "V1agra Ch3ap Online Buy Now!!!"; do
    PID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='$title' AND post_type='post' ORDER BY ID DESC LIMIT 1")
    if [ -n "$PID" ]; then
        POST_IDS="$POST_IDS $PID"
        # Verify it's in Uncategorized
        CATS=$(get_post_categories "$PID")
        echo "  Post '$title' (ID: $PID): categories=[$CATS]"
    fi
done

echo "$POST_IDS" | sudo tee /tmp/audit_post_ids > /dev/null
sudo chmod 666 /tmp/audit_post_ids

TOTAL_POST_COUNT=$(wp_cli post list --post_type=post --post_status=any --format=count)
echo "Total posts (all statuses): $TOTAL_POST_COUNT"
echo "$TOTAL_POST_COUNT" | sudo tee /tmp/initial_audit_post_count > /dev/null
sudo chmod 666 /tmp/initial_audit_post_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# ============================================================
# Ensure Firefox is running
# ============================================================
echo ""
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/?autologin=admin' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Created 6 posts: 5 legitimate (wrong categories) + 1 spam."
echo "Agent must recategorize, delete spam, publish drafts, add tags."
