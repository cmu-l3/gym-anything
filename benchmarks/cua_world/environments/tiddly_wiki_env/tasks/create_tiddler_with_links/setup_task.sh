#!/bin/bash
echo "=== Setting up create_tiddler_with_links task ==="

source /workspace/scripts/task_utils.sh

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count
echo "Initial tiddler count: $INITIAL_COUNT"

# Verify that the link target tiddlers exist
for target in "Agile Methodology Overview" "Version Control Best Practices"; do
    if [ "$(tiddler_exists "$target")" = "true" ]; then
        echo "Link target '$target' exists"
    else
        echo "WARNING: Link target '$target' not found!"
    fi
done

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
fi

DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

take_screenshot /tmp/links_initial.png

echo "=== Task setup complete ==="
