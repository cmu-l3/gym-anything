#!/bin/bash
echo "=== Setting up style_tags_triage_dashboard task ==="

source /workspace/scripts/task_utils.sh

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count

# Generate real Godot Engine GitHub issues as tiddlers
echo "Generating Godot Engine issue tiddlers..."
ISSUES=(
    "Vulkan Broken screen space reflections|bug critical|Screen space reflections are broken on Vulkan backend when using MSAA."
    "Crash on exiting the editor|bug critical|Editor segfaults on exit in 4.2."
    "Add support for 3D pathfinding|enhancement|Navigation mesh support for true 3D environments."
    "Document new networking API|documentation|MultiplayerAPI needs updated docs for 4.x."
    "Shadow mapping artifacts on directional lights|bug|Peter-panning visible on low bias."
    "Implement WebGPU backend|enhancement|Add support for the new WebGPU standard."
    "Fix typo in Node3D transform tutorial|documentation|Matrix multiplication order is wrong."
    "Audio popping when playing overlapping samples|bug|AudioStreamPlayer has crackling issues."
    "Add dark mode theme support for the editor|enhancement|Catppuccin or similar dark theme defaults."
    "Memory leak in physics server|bug critical|RigidBody3D leaks memory when continuously spawned."
    "Update GDScript style guide|documentation|Add conventions for typed arrays."
    "Editor freezes when importing large GLTF|bug|Importing 50MB+ models locks the main thread."
    "Add support for custom shaders in Particles|enhancement|Allow writing raw GLSL for particle processing."
    "Document the AnimationTree state machine|documentation|Examples are missing for transitions."
    "Fix physics jitter at high frame rates|bug|Interpolation breaks >144hz."
)

for issue in "${ISSUES[@]}"; do
    TITLE=$(echo "$issue" | cut -d'|' -f1)
    TAGS=$(echo "$issue" | cut -d'|' -f2)
    TEXT=$(echo "$issue" | cut -d'|' -f3)
    
    cat > "$TIDDLER_DIR/$TITLE.tid" << EOF
title: $TITLE
tags: $TAGS
type: text/vnd.tiddlywiki

$TEXT
EOF
    chown ga:ga "$TIDDLER_DIR/$TITLE.tid"
done

# Restart TiddlyWiki to ensure all new tiddlers are loaded
pkill -f "tiddlywiki" 2>/dev/null || true
sleep 2
su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for TiddlyWiki server
echo "Waiting for TiddlyWiki server..."
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running"
        break
    fi
    sleep 1
done

# Focus Firefox window and refresh to show new issues
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
    sleep 1
    DISPLAY=:1 xdotool key F5
    sleep 3
fi

take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="