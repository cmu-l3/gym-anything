#!/bin/bash
# Task setup: post_input_data
# Opens the Input API documentation page (/input/api) where the agent can see
# their write API key and construct a GET request URL to post input data.

source /workspace/scripts/task_utils.sh

echo "=== Setting up post_input_data task ==="

wait_for_emoncms

# Navigate to Input API Helper page
launch_firefox_to "http://localhost/input/api" 5

# Take a starting screenshot
take_screenshot /tmp/task_post_input_data_start.png

echo "=== Task setup complete: post_input_data ==="
