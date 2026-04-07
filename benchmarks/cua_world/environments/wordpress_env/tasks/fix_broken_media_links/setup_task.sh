#!/bin/bash
# Setup script for fix_broken_media_links task

echo "=== Setting up fix_broken_media_links task ==="

source /workspace/scripts/task_utils.sh

# ============================================================
# 1. Download Real Recovered Media to Desktop/Documents
# ============================================================
MEDIA_DIR="/home/ga/Documents/recovered_media"
mkdir -p "$MEDIA_DIR"

echo "Downloading sample images..."
# Using reliable Wikimedia Commons URLs for public domain / CC images
wget -q -O "$MEDIA_DIR/guggenheim.jpg" "https://upload.wikimedia.org/wikipedia/commons/thumb/1/10/Guggenheim_Museum%2C_Bilbao%2C_July_2010_%2805%29.JPG/800px-Guggenheim_Museum%2C_Bilbao%2C_July_2010_%2805%29.JPG" || touch "$MEDIA_DIR/guggenheim.jpg"
wget -q -O "$MEDIA_DIR/bauhaus.jpg" "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Bauhaus_Dessau.jpg/800px-Bauhaus_Dessau.jpg" || touch "$MEDIA_DIR/bauhaus.jpg"
wget -q -O "$MEDIA_DIR/fallingwater.jpg" "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f0/Fallingwater_-_Wright.jpg/800px-Fallingwater_-_Wright.jpg" || touch "$MEDIA_DIR/fallingwater.jpg"

chown -R ga:ga "$MEDIA_DIR"

# ============================================================
# 2. Inject Broken Post
# ============================================================
echo "Injecting target post with broken media blocks..."
cd /var/www/html/wordpress

BROKEN_CONTENT='<!-- wp:paragraph -->
<p>Modern architecture has produced some of the most iconic buildings in the world. As we look through the evolution of functional design, several structures stand out as masterpieces.</p>
<!-- /wp:paragraph -->

<!-- wp:heading -->
<h2>The Guggenheim Museum Bilbao</h2>
<!-- /wp:heading -->

<!-- wp:image {"url":"http://legacy-site.local/images/guggenheim.jpg"} -->
<figure class="wp-block-image"><img src="http://legacy-site.local/images/guggenheim.jpg" alt="Broken Guggenheim"/></figure>
<!-- /wp:image -->

<!-- wp:paragraph -->
<p>Frank Gehry redefined modern museum architecture with this titanium-clad masterpiece.</p>
<!-- /wp:paragraph -->

<!-- wp:heading -->
<h2>The Bauhaus Building</h2>
<!-- /wp:heading -->

<!-- wp:image {"url":"http://legacy-site.local/images/bauhaus.jpg"} -->
<figure class="wp-block-image"><img src="http://legacy-site.local/images/bauhaus.jpg" alt="Broken Bauhaus"/></figure>
<!-- /wp:image -->

<!-- wp:paragraph -->
<p>Walter Gropius designed the Dessau building to reflect the school’s core philosophy: functionalism and the unity of art and technology.</p>
<!-- /wp:paragraph -->

<!-- wp:heading -->
<h2>Fallingwater</h2>
<!-- /wp:heading -->

<!-- wp:image {"url":"http://legacy-site.local/images/fallingwater.jpg"} -->
<figure class="wp-block-image"><img src="http://legacy-site.local/images/fallingwater.jpg" alt="Broken Fallingwater"/></figure>
<!-- /wp:image -->

<!-- wp:paragraph -->
<p>Frank Lloyd Wright integrated this beautiful home directly into the natural waterfall environment, representing organic architecture.</p>
<!-- /wp:paragraph -->'

wp post create \
    --post_type=post \
    --post_status=publish \
    --post_title="Exploring Modern Architecture Masterpieces" \
    --post_content="$BROKEN_CONTENT" \
    --allow-root 2>&1

# Get the ID of the created post
TARGET_POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='Exploring Modern Architecture Masterpieces' AND post_type='post' ORDER BY ID DESC LIMIT 1")
echo "$TARGET_POST_ID" | sudo tee /tmp/target_post_id > /dev/null
sudo chmod 666 /tmp/target_post_id

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# ============================================================
# 3. Ensure Firefox is Running
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
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