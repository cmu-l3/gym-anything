#!/bin/bash
set -euo pipefail

echo "=== Setting up create_project_forums task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Wait for Redmine to be available
wait_for_http "$REDMINE_BASE_URL/login" 120

# Read seed data to find a target project
SEED_FILE="/tmp/redmine_seed_result.json"
if [ ! -f "$SEED_FILE" ]; then
    echo "ERROR: Seed result file not found at $SEED_FILE"
    exit 1
fi

# Get first project identifier and numeric ID
PROJECT_IDENTIFIER=$(jq -r '.projects[0].identifier' "$SEED_FILE")
PROJECT_NUM_ID=$(jq -r '.projects[0].id' "$SEED_FILE")
PROJECT_NAME=$(jq -r '.projects[0].name' "$SEED_FILE")

if [ -z "$PROJECT_IDENTIFIER" ] || [ "$PROJECT_IDENTIFIER" = "null" ]; then
    echo "ERROR: No project found in seed data"
    exit 1
fi

echo "Target project: $PROJECT_NAME (identifier: $PROJECT_IDENTIFIER)"
echo "$PROJECT_IDENTIFIER" > /tmp/task_project_identifier.txt

# Enable Boards module for the project via Rails runner
# We need to ensure the module is enabled so the agent *can* use forums,
# but we want the agent to do the configuration.
# Actually, the task description implies the module needs to be used. 
# Usually, modules need to be enabled in Project Settings.
# The task instruction says: "go to the project's Settings page and find the Forums tab."
# This implies the module MIGHT be enabled, but if it's not, the tab won't be there.
# To be safe and focused on the task goal (creating forums), we force-enable the module 
# so the UI isn't confusingly empty.

REDMINE_SKB="redmine_env_secret_key_base_do_not_use_in_production_xyz123"

echo "Enabling Boards module for project $PROJECT_IDENTIFIER..."
docker exec -e SECRET_KEY_BASE="$REDMINE_SKB" redmine \
    bundle exec rails runner "
        p = Project.find('$PROJECT_IDENTIFIER')
        mods = p.enabled_module_names
        unless mods.include?('boards')
            p.enabled_module_names = mods + ['boards']
            p.save!
            puts 'Boards module enabled'
        else
            puts 'Boards module already enabled'
        end
    " -e production 2>/dev/null || echo "WARNING: Could not enable boards module via rails runner"

# Remove any existing boards (clean state)
echo "Cleaning existing boards..."
docker exec -e SECRET_KEY_BASE="$REDMINE_SKB" redmine \
    bundle exec rails runner "
        p = Project.find('$PROJECT_IDENTIFIER')
        p.boards.destroy_all
        puts 'Cleaned existing boards'
    " -e production 2>/dev/null || echo "WARNING: Could not clean boards"

# Start Firefox navigated to the project overview
PROJECT_URL="$REDMINE_BASE_URL/projects/$PROJECT_IDENTIFIER"
echo "Starting Firefox at $PROJECT_URL"

# Login and navigate
ensure_redmine_logged_in "$PROJECT_URL"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved"

echo "=== Task setup complete ==="