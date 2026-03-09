#!/bin/bash
# Task setup: create_work_package
# Navigates Firefox to the E-Commerce Platform work packages list.
# Agent will create a new work package from there.

source /workspace/scripts/task_utils.sh

echo "=== Setting up create_work_package task ==="

wait_for_openproject

launch_firefox_to "http://localhost:8080/projects/ecommerce-platform/work_packages" 5

take_screenshot /tmp/task_create_work_package_start.png

echo "=== Task setup complete: create_work_package ==="
