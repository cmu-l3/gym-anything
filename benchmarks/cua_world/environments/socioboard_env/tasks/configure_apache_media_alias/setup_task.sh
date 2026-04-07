#!/bin/bash
echo "=== Setting up configure_apache_media_alias task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
sudo rm -f /tmp/task_result.json 2>/dev/null || true

# 1. Create the target directory and set permissions
TARGET_DIR="/var/lib/agency_stock_media"
sudo mkdir -p "$TARGET_DIR"

# 2. Download a real stock image (Public Domain image from Wikimedia Commons)
echo "Downloading sample stock image..."
sudo curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b2/Monarch_Butterfly_Danaus_plexippus_Feeding_Down_3008px.jpg/800px-Monarch_Butterfly_Danaus_plexippus_Feeding_Down_3008px.jpg" -o "$TARGET_DIR/monarch.jpg" || \
    sudo convert -size 800x600 pattern:checkerboard "$TARGET_DIR/monarch.jpg" # Fallback if network fails

# Ensure permissions allow web server to read it
sudo chmod -R 755 "$TARGET_DIR"
sudo chown -R www-data:www-data "$TARGET_DIR"

# 3. Clean up any cheating directories from previous aborted runs
CHEAT_DIR="/opt/socioboard/socioboard-web-php/public/stock-media"
sudo rm -rf "$CHEAT_DIR"

# 4. Clean up any existing Alias configurations in Apache to ensure a pristine state
sudo sed -i '/Alias \/stock-media/d' /etc/apache2/sites-available/*.conf 2>/dev/null || true
sudo sed -i '/<Directory \/var\/lib\/agency_stock_media>/,/<\/Directory>/d' /etc/apache2/sites-available/*.conf 2>/dev/null || true
sudo systemctl reload apache2

# Wait for Socioboard / Apache to be ready
if ! wait_for_http "http://localhost/" 120; then
  echo "ERROR: Socioboard not reachable at http://localhost/"
  exit 1
fi

# 5. Open Firefox to localhost so the agent has a starting point
ensure_firefox_running "http://localhost"
sleep 2

# Open a terminal for the agent to use
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Take initial screenshot showing the initial state
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured: /tmp/task_initial.png"

echo "=== Task setup complete ==="