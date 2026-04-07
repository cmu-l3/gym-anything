#!/bin/bash
echo "=== Setting up build_dynamic_progress_dashboard task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create seed data for game levels and tasks
WIKI_TIDDLERS="/home/ga/mywiki/tiddlers"
mkdir -p "$WIKI_TIDDLERS"

# Function to create a level
create_level() {
    local title="$1"
    cat > "$WIKI_TIDDLERS/$title.tid" << EOF
title: $title
tags: Level
type: text/vnd.tiddlywiki

This is the $title game level.
EOF
}

# Function to create a task
create_task() {
    local title="$1"
    local level="$2"
    local status="$3"
    cat > "$WIKI_TIDDLERS/$title.tid" << EOF
title: $title
tags: [[$level]] Task
status: $status
type: text/vnd.tiddlywiki

Task for $level.
EOF
}

echo "Generating seed levels and tasks..."

# 1. Clockwork Tower (4 tasks: 1 done, 1 in-progress, 2 todo -> 25%)
create_level "Clockwork Tower"
create_task "Model main gears" "Clockwork Tower" "done"
create_task "Rig elevator platform" "Clockwork Tower" "in-progress"
create_task "Sound design for ticking" "Clockwork Tower" "todo"
create_task "Lighting pass" "Clockwork Tower" "todo"

# 2. Crystal Caverns (4 tasks: 2 done, 1 in-progress, 1 todo -> 50%)
create_level "Crystal Caverns"
create_task "Sculpt stalactites" "Crystal Caverns" "done"
create_task "Glowing mushroom assets" "Crystal Caverns" "done"
create_task "Echo sound effects" "Crystal Caverns" "in-progress"
create_task "Water reflections" "Crystal Caverns" "todo"

# 3. Magma Core (5 tasks: 1 done, 1 in-progress, 3 todo -> 20%)
create_level "Magma Core"
create_task "Lava shader" "Magma Core" "done"
create_task "Volcano particle effects" "Magma Core" "in-progress"
create_task "Fire enemy variations" "Magma Core" "todo"
create_task "Heat distortion post-process" "Magma Core" "todo"
create_task "Boss arena layout" "Magma Core" "todo"

# 4. Neon City (2 tasks: 0 done, 1 in-progress, 1 todo -> 0%)
create_level "Neon City"
create_task "Neon signs" "Neon City" "todo"
create_task "Flying cars traffic system" "Neon City" "in-progress"

# 5. Whispering Woods (2 tasks: 2 done, 0 in-progress, 0 todo -> 100%)
create_level "Whispering Woods"
create_task "Tree canopy generator" "Whispering Woods" "done"
create_task "Fog volumes" "Whispering Woods" "done"

# Fix ownership
chown -R ga:ga /home/ga/mywiki

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not accessible, restarting..."
    su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"
    sleep 3
fi

# Ensure Firefox is focused
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

take_screenshot /tmp/dashboard_initial.png

echo "=== Task setup complete ==="