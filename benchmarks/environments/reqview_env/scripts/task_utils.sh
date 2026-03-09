#!/bin/bash
# Shared utilities for ReqView tasks
# NOTE: Do NOT use set -euo pipefail here (breaks sourcing per pattern #25)

REQVIEW_BIN=""
for candidate in /usr/bin/reqview /opt/ReqView/reqview /usr/local/bin/reqview; do
    if [ -f "$candidate" ]; then
        REQVIEW_BIN="$candidate"
        break
    fi
done
if [ -z "$REQVIEW_BIN" ]; then
    REQVIEW_BIN=$(find /opt /usr -name "reqview" -type f 2>/dev/null | head -1 || true)
fi

export REQVIEW_BIN
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Take a screenshot and save to a path
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$path" 2>/dev/null || true
}

# Wait for ReqView window to appear
wait_for_reqview() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "reqview\|ReqView"; then
            echo "ReqView window ready after ${elapsed}s"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "WARNING: ReqView did not appear within ${timeout}s"
    return 1
}

# Launch ReqView with a specific project folder using reqview open -p
launch_reqview_with_project() {
    local project_path="$1"
    pkill -f "reqview" 2>/dev/null || true
    sleep 2
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority nohup '${REQVIEW_BIN}' open -p '${project_path}' > /tmp/reqview_task.log 2>&1 &" || true
    wait_for_reqview 90
    sleep 5  # Extra time for the project to fully load
}

# Dismiss dialogs with Escape
dismiss_dialogs() {
    for i in 1 2 3; do
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
        sleep 0.5
    done
}

# Maximize the ReqView window
maximize_window() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "ReqView" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
}

# Open the SRS document by clicking it in the left project tree.
# After launch_reqview_with_project, the project tree is visible but no document
# is open in the editor. This function clicks "SRS" in the tree to open it.
# Args: extra_wait (default 4) — seconds to wait after click for document to render
open_srs_document() {
    local extra_wait="${1:-4}"
    echo "Opening SRS document from project tree..."
    # The project tree (fully expanded) shows items in this order:
    #   INF / [L1: Stakeholders: NEEDS, ASVS, RISKS] / [L2: System: SRS, TESTS] / [L3: Design: ARCH]
    # On a 1920x1080 display, "SRS" is at approximately x=114, y=415.
    # (Derived from visual grounding measurements: 1280x720 scale x≈76, y≈276 → ×1.5)
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 114 415 click 1 2>/dev/null || true
    sleep "$extra_wait"
    echo "SRS document open"
}

# Copy the base example project to a task-specific fresh copy
# Returns the path to the task project directory
setup_task_project() {
    local task_name="$1"
    local task_project_dir="/home/ga/Documents/ReqView/${task_name}_project"

    rm -rf "$task_project_dir" 2>/dev/null || true
    mkdir -p "$task_project_dir"

    # Try cached example project first (created by setup_reqview.sh warm-up)
    local base_project="/home/ga/Documents/ReqView/ExampleProject"
    if [ -d "$base_project" ] && [ -f "$base_project/project.json" ]; then
        cp -r "$base_project/." "$task_project_dir/"
        chown -R ga:ga "$task_project_dir"
        echo "Copied example project to $task_project_dir" >&2
    elif [ -d /workspace/data/ExampleProject ] && [ -f /workspace/data/ExampleProject/project.json ]; then
        # Fallback: workspace data (mounted read-only, but we copy to writable location)
        cp -r /workspace/data/ExampleProject/. "$task_project_dir/"
        chown -R ga:ga "$task_project_dir"
        echo "Copied example project from workspace data to $task_project_dir" >&2
    else
        echo "WARNING: No example project found for task setup" >&2
    fi

    echo "$task_project_dir"
}
