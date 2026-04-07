#!/bin/bash
echo "=== Setting up create_service_dependency_map task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any pre-existing tiddlers that might conflict with this task
echo "Cleaning up any existing target tiddlers..."
TARGETS=(
    "UserService" "ProductCatalog" "InventoryService"
    "PaymentGateway" "OrderService" "NotificationService"
    "Service Dependency Map" "Service_Dependency_Map"
)

for target in "${TARGETS[@]}"; do
    sanitized=$(echo "$target" | sed 's/[\/\\:*?"<>|]/_/g')
    rm -f "$TIDDLER_DIR/${sanitized}.tid" 2>/dev/null || true
    # Also handle case-insensitive removals
    find "$TIDDLER_DIR" -maxdepth 1 -iname "${sanitized}.tid" -delete 2>/dev/null || true
done

# Ensure TiddlyWiki server is running
if ! curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "Starting TiddlyWiki server..."
    su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"
    sleep 5
fi

# Ensure Firefox is running and focused
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|tiddly"; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Maximize Firefox window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any potential dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="