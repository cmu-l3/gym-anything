#!/bin/bash
# Shared utilities for all IntelliJ IDEA tasks

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Wait for IntelliJ window to appear
wait_for_intellij() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "intellij\|idea"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Wait for IntelliJ to fully load a project (not just the welcome screen)
# This uses polling to detect when the project window title contains the project name
wait_for_project_loaded() {
    local project_name="${1:-}"
    local timeout="${2:-120}"
    local elapsed=0

    echo "Waiting for IntelliJ to load project: $project_name"

    while [ $elapsed -lt $timeout ]; do
        # Check if window title contains project name (indicates project is loaded)
        if [ -n "$project_name" ]; then
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$project_name"; then
                echo "Project window detected after ${elapsed}s"
                sleep 5  # Additional wait for UI to stabilize
                return 0
            fi
        else
            # If no project name, just check for IntelliJ window that's not the welcome screen
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "intellij\|idea" | grep -v -qi "welcome"; then
                echo "Project window detected after ${elapsed}s"
                sleep 5
                return 0
            fi
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "WARNING: Project not fully loaded within ${timeout}s"
    return 1
}

# Dismiss any dialogs that might appear (Trust, Tips, etc.)
dismiss_dialogs() {
    local max_attempts="${1:-5}"
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        # Press Escape to dismiss dialogs
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 1
        attempt=$((attempt + 1))
    done
}

# Handle Trust Project dialog by clicking the "Trust Project" button
# This uses xdotool to search for and click the trust button
handle_trust_dialog() {
    local max_attempts="${1:-10}"
    local attempt=0

    echo "Checking for Trust Project dialog..."

    while [ $attempt -lt $max_attempts ]; do
        # Take a screenshot to check dialog state
        take_screenshot /tmp/trust_check_${attempt}.png

        # Check if a dialog with "Trust" text is visible by looking at window titles
        local dialog_visible=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "trust" || true)

        if [ -n "$dialog_visible" ]; then
            echo "Trust dialog detected, clicking Trust Project button..."

            # Focus the dialog window
            local trust_wid=$(DISPLAY=:1 wmctrl -l | grep -i "trust" | head -1 | awk '{print $1}')
            if [ -n "$trust_wid" ]; then
                DISPLAY=:1 wmctrl -ia "$trust_wid" 2>/dev/null || true
            fi

            # Press Tab to navigate to Trust Project button (usually second button)
            # Then press Enter to click it
            sleep 0.5
            DISPLAY=:1 xdotool key Tab 2>/dev/null || true
            sleep 0.3
            DISPLAY=:1 xdotool key Return 2>/dev/null || true
            sleep 2

            # Verify dialog is gone
            if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "trust"; then
                echo "Trust dialog dismissed successfully"
                return 0
            fi
        else
            # No trust dialog visible, we're good
            echo "No Trust dialog detected"
            return 0
        fi

        sleep 2
        attempt=$((attempt + 1))
    done

    echo "WARNING: Could not dismiss Trust dialog after $max_attempts attempts"
    return 1
}

# Focus and maximize IntelliJ window
focus_intellij_window() {
    local WID=$(DISPLAY=:1 wmctrl -l | grep -i "intellij\|idea" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "IntelliJ window focused and maximized"
        return 0
    fi
    return 1
}

# Complete setup sequence for task: open project, wait for load, dismiss dialogs
setup_intellij_project() {
    local project_path="$1"
    local project_name="${2:-$(basename $project_path)}"
    local timeout="${3:-120}"

    echo "Opening project: $project_path"

    # Launch IntelliJ with the project
    su - ga -c "DISPLAY=:1 /opt/idea/bin/idea.sh '$project_path' > /tmp/intellij_task.log 2>&1 &"

    # Initial wait for IntelliJ to start loading
    sleep 10

    # Handle any Trust Project dialog that might appear
    handle_trust_dialog 5

    # Wait for project to fully load
    wait_for_project_loaded "$project_name" "$timeout"

    # Handle Trust dialog again (might appear after indexing)
    handle_trust_dialog 3

    # Dismiss any other dialogs (tips, notifications)
    dismiss_dialogs 3

    # Focus and maximize
    focus_intellij_window

    # Final stabilization wait
    sleep 3

    echo "Project setup complete"
}

# Safe JSON write (handles permission issues)
write_json_result() {
    local json_content="$1"
    local target_path="${2:-/tmp/task_result.json}"

    TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
    echo "$json_content" > "$TEMP_JSON"

    rm -f "$target_path" 2>/dev/null || sudo rm -f "$target_path" 2>/dev/null || true
    cp "$TEMP_JSON" "$target_path" 2>/dev/null || sudo cp "$TEMP_JSON" "$target_path"
    chmod 666 "$target_path" 2>/dev/null || sudo chmod 666 "$target_path" 2>/dev/null || true
    rm -f "$TEMP_JSON"
}

# Run Maven in a project directory
run_maven() {
    local project_dir="$1"
    local goal="${2:-compile}"
    local output_file="${3:-/tmp/maven_output.log}"

    cd "$project_dir" && \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    mvn "$goal" -q > "$output_file" 2>&1
    return $?
}
