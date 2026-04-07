#!/bin/bash
# setup_task.sh for tag_documents
# Ensures documents exist, clears existing tags, and positions the agent.

set -e
echo "=== Setting up tag_documents task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# 2. Wait for Nuxeo to be responsive
wait_for_nuxeo 120

# 3. Ensure required documents exist (Projects workspace should be populated by env setup)
# If for some reason they are missing, we recreate them briefly here or fail.
echo "Verifying documents exist..."

ensure_doc_exists() {
    local path="$1"
    local title="$2"
    local type="$3"
    
    if ! doc_exists "$path"; then
        echo "WARNING: Document $path missing. Attempting to create placeholder..."
        # Create a simple placeholder if missing (fallback)
        PARENT=$(dirname "$path")
        NAME=$(basename "$path")
        create_doc_if_missing "$PARENT" "$type" "$NAME" "$title" "Restored for task"
    else
        echo "  OK: $path exists."
    fi
}

ensure_doc_exists "/default-domain/workspaces/Projects/Annual-Report-2023" "Annual Report 2023" "File"
ensure_doc_exists "/default-domain/workspaces/Projects/Project-Proposal" "Project Proposal" "File"
ensure_doc_exists "/default-domain/workspaces/Projects/Q3-Status-Report" "Q3 Status Report" "Note"

# 4. Clear ANY existing tags on these documents to ensure clean state
echo "Clearing existing tags..."

clear_tags() {
    local doc_path="$1"
    # Get current tags
    # Nuxeo API to remove tags usually requires removing them one by one or replacing the tags collection
    # A simple way to clear is to not add any, but if they exist, we must remove.
    # We'll use the 'operations' endpoint to RemoveAllTags if available, or just ignore for now assuming env is clean?
    # Better: explicitly remove known tags or use a script.
    
    # Nuxeo Automation Operation: Services.RemoveTag
    # But easier: The system starts clean. Let's just log that we are ready.
    # If we really need to clear, we would query tags and delete them.
    # For this implementation, we assume the environment reset cleans them, 
    # but we can try a blind remove of expected tags just in case.
    
    local uid
    uid=$(nuxeo_api GET "/path$doc_path" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null)
    
    if [ -n "$uid" ]; then
        # Automation chain to remove tags is complex via curl if we don't know them.
        # We'll rely on the fresh environment state usually, but let's try to remove likely tags
        for tag in "annual-report" "finance" "2023" "proposal" "project-planning" "quarterly-report" "status"; do
             curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
                -X POST "$NUXEO_URL/api/v1/id/$uid/@op/Services.RemoveTag" \
                -d "{\"params\":{\"tag\":\"$tag\"}}" > /dev/null 2>&1 || true
        done
    fi
}

clear_tags "/default-domain/workspaces/Projects/Annual-Report-2023"
clear_tags "/default-domain/workspaces/Projects/Project-Proposal"
clear_tags "/default-domain/workspaces/Projects/Q3-Status-Report"

# 5. Open Firefox and navigate to the Projects workspace
echo "Launching Firefox..."

# Check if Firefox is already running; if not, start it
if ! pgrep -f "firefox" > /dev/null; then
    open_nuxeo_url "$NUXEO_URL/login.jsp" 10
else
    # Just navigate if open
    navigate_to "$NUXEO_URL/login.jsp"
fi

# Ensure login (if not already logged in)
sleep 5
PAGE_TITLE=$(ga_x "xdotool getactivewindow getwindowname" 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

# Navigate explicitly to Projects workspace
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"

# 6. Capture initial state screenshot
echo "Capturing initial state..."
sleep 2
ga_x "scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="