#!/bin/bash
# Task setup: create_wiki_page
# Navigates Firefox to the E-Commerce Platform wiki.

source /workspace/scripts/task_utils.sh

echo "=== Setting up create_wiki_page task ==="

wait_for_openproject

launch_firefox_to "http://localhost:8080/projects/ecommerce-platform/wiki" 5

take_screenshot /tmp/task_create_wiki_page_start.png

echo "=== Task setup complete: create_wiki_page ==="
