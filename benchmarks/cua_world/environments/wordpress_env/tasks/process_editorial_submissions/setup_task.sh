#!/bin/bash
echo "=== Setting up process_editorial_submissions task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# ============================================================
# Prepare Images in ~/Downloads
# ============================================================
echo "Downloading reference images..."
mkdir -p /home/ga/Downloads
cd /home/ga/Downloads

# Download real images from Wikimedia Commons
curl -sL -o roman_telescope.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e0/Nancy_Grace_Roman_Space_Telescope.jpg/800px-Nancy_Grace_Roman_Space_Telescope.jpg" || \
wget -qO roman_telescope.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e0/Nancy_Grace_Roman_Space_Telescope.jpg/800px-Nancy_Grace_Roman_Space_Telescope.jpg"

curl -sL -o hubble_galaxy.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/6/69/NASA-HS201427a-Hubble-Galaxy-NGC1433-20140828.jpg/800px-NASA-HS201427a-Hubble-Galaxy-NGC1433-20140828.jpg" || \
wget -qO hubble_galaxy.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/6/69/NASA-HS201427a-Hubble-Galaxy-NGC1433-20140828.jpg/800px-NASA-HS201427a-Hubble-Galaxy-NGC1433-20140828.jpg"

# Fallback just in case network blocks downloads
if [ ! -s roman_telescope.jpg ]; then
    echo "Creating fallback roman_telescope image"
    convert -size 800x600 xc:navy -fill white -gravity center -pointsize 40 -annotate 0 "Roman Telescope" roman_telescope.jpg 2>/dev/null || touch roman_telescope.jpg
fi
if [ ! -s hubble_galaxy.jpg ]; then
    echo "Creating fallback hubble_galaxy image"
    convert -size 800x600 xc:purple -fill white -gravity center -pointsize 40 -annotate 0 "Hubble Galaxy" hubble_galaxy.jpg 2>/dev/null || touch hubble_galaxy.jpg
fi

chown -R ga:ga /home/ga/Downloads
chmod -R 755 /home/ga/Downloads

# ============================================================
# Create Pending Posts Content
# ============================================================
cd /var/www/html/wordpress

# Clean up any existing pending posts to ensure clean state
PENDING_IDS=$(wp post list --post_type=post --post_status=pending --format=ids --allow-root 2>/dev/null || echo "")
if [ -n "$PENDING_IDS" ]; then
    echo "Cleaning up existing pending posts..."
    wp post delete $PENDING_IDS --force --allow-root >/dev/null
fi

echo "Creating the three pending editorial submissions..."

SPAM_ID=$(wp post create --post_type=post --post_status=pending \
    --post_title="Boost your Domain Authority with Casino Links SEO" \
    --post_content="Buy cheap links for casino SEO. 100% guaranteed domain authority boost! Best prices for ranking on Google page 1." \
    --porcelain --allow-root)

ART1_ID=$(wp post create --post_type=post --post_status=pending \
    --post_title="NASA's Roman Mission to Probe Cosmic 'Fossils'" \
    --post_content="<!-- wp:paragraph -->
<p><strong>[EDITOR: Please remove this note before publishing]</strong></p>
<!-- /wp:paragraph -->
<!-- wp:paragraph -->
<p>The Nancy Grace Roman Space Telescope will provide a panoramic field of view that is 100 times greater than Hubble's, revealing countless previously unseen stars and galaxies. By studying these ancient cosmic structures, astronomers hope to understand the universe's expansion history and uncover the nature of dark energy.</p>
<!-- /wp:paragraph -->" \
    --porcelain --allow-root)

ART2_ID=$(wp post create --post_type=post --post_status=pending \
    --post_title="Hubble Views a Galactic Monster" \
    --post_content="<!-- wp:paragraph -->
<p><strong>[EDITOR: Please remove this note before publishing. Also make sure to add the featured image!]</strong></p>
<!-- /wp:paragraph -->
<!-- wp:paragraph -->
<p>NASA's Hubble Space Telescope has captured a stunning image of a massive galaxy cluster, revealing the gravitational lensing effect first predicted by Albert Einstein. The cluster's immense gravity acts as a cosmic magnifying glass, bending the light of even more distant galaxies behind it into glowing, distorted arcs.</p>
<!-- /wp:paragraph -->" \
    --porcelain --allow-root)

echo "Saving post IDs for verification tracking..."
cat > /tmp/task_post_ids.json << EOF
{
    "spam_id": $SPAM_ID,
    "art1_id": $ART1_ID,
    "art2_id": $ART2_ID
}
EOF
chmod 666 /tmp/task_post_ids.json

# ============================================================
# Ensure Firefox is ready
# ============================================================
echo "Ensuring Firefox is running and focused on WP admin..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php?post_status=pending&post_type=post' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
else
    # If it's already running, just focus it
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 1
    fi
fi

# Take initial screenshot for the record
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="