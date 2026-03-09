#!/bin/bash
# Task setup: view_feed_graph
# Opens the Graph module (advanced graphing page).

source /workspace/scripts/task_utils.sh

echo "=== Setting up view_feed_graph task ==="

wait_for_emoncms

# Navigate to Graph page
launch_firefox_to "http://localhost/graph" 5

# Take a starting screenshot
take_screenshot /tmp/task_view_feed_graph_start.png

echo "=== Task setup complete: view_feed_graph ==="
