#!/bin/bash
echo "=== Setting up build_kanban_board_system task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create seed task tiddlers
echo "Creating seed task tiddlers..."

cat << 'EOF' > "$TIDDLER_DIR/Task_1_DB.tid"
title: Design Database Schema
tags: Task
kanban-status: To Do

Create the initial ERD and SQL schema for the application.
EOF

cat << 'EOF' > "$TIDDLER_DIR/Task_2_CI.tid"
title: Setup CI CD Pipeline
tags: Task
kanban-status: To Do

Configure GitHub Actions for automated testing and deployment.
EOF

cat << 'EOF' > "$TIDDLER_DIR/Task_3_Auth.tid"
title: Implement Auth API
tags: Task
kanban-status: In Progress

Build JWT-based authentication endpoints.
EOF

cat << 'EOF' > "$TIDDLER_DIR/Task_4_UI.tid"
title: Create UI Wireframes
tags: Task
kanban-status: In Progress

Design Figma mockups for the main dashboard.
EOF

cat << 'EOF' > "$TIDDLER_DIR/Task_5_Tests.tid"
title: Write Unit Tests
tags: Task
kanban-status: Done

Achieve 80% test coverage on core utility functions.
EOF

cat << 'EOF' > "$TIDDLER_DIR/Task_6_Docker.tid"
title: Configure Docker
tags: Task
kanban-status: Done

Create Dockerfile and docker-compose.yml for local development.
EOF

chown ga:ga "$TIDDLER_DIR"/Task_*.tid

# Record initial counts
INITIAL_TASK_COUNT=$(find_tiddlers_with_tag "Task" | wc -l)
echo "$INITIAL_TASK_COUNT" > /tmp/initial_task_count
echo "Seeded $INITIAL_TASK_COUNT tasks."

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
fi

# Focus Firefox and refresh to ensure new tiddlers are loaded
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key F5 2>/dev/null || true
sleep 3

# Take initial screenshot
take_screenshot /tmp/kanban_initial.png

echo "=== Task setup complete ==="