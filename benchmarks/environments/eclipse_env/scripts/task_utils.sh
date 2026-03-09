#!/bin/bash
# Shared utilities for all Eclipse IDE tasks

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Wait for Eclipse window to appear
wait_for_eclipse() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "eclipse\|java"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Wait for Eclipse to fully load a project (not just the welcome screen)
# This uses polling to detect when the project window title contains the project name
wait_for_project_loaded() {
    local project_name="${1:-}"
    local timeout="${2:-120}"
    local elapsed=0

    echo "Waiting for Eclipse to load project: $project_name"

    while [ $elapsed -lt $timeout ]; do
        # Check if window title contains project name (indicates project is loaded)
        if [ -n "$project_name" ]; then
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$project_name"; then
                echo "Project window detected after ${elapsed}s"
                sleep 5  # Additional wait for UI to stabilize
                return 0
            fi
        else
            # If no project name, just check for Eclipse window that's not the welcome screen
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "eclipse\|java" | grep -v -qi "welcome"; then
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

# Dismiss any dialogs that might appear (Tips, Welcome, etc.)
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

# Focus and maximize Eclipse window
focus_eclipse_window() {
    local WID=$(DISPLAY=:1 wmctrl -l | grep -i "eclipse\|java" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "Eclipse window focused and maximized"
        return 0
    fi
    return 1
}

# Close welcome tab in Eclipse
close_welcome_tab() {
    # Eclipse welcome tab can be closed with Ctrl+W
    DISPLAY=:1 xdotool key ctrl+w 2>/dev/null || true
    sleep 1
}

# Import a project into Eclipse workspace
import_project_to_eclipse() {
    local project_path="$1"
    local project_name="${2:-$(basename $project_path)}"

    echo "Importing project: $project_path"

    # Copy project to workspace
    cp -r "$project_path" "/home/ga/eclipse-workspace/$project_name"
    chown -R ga:ga "/home/ga/eclipse-workspace/$project_name"

    echo "Project copied to workspace"
}

# Complete setup sequence for task: open project, wait for load, dismiss dialogs
setup_eclipse_project() {
    local project_path="$1"
    local project_name="${2:-$(basename $project_path)}"
    local timeout="${3:-120}"

    echo "Setting up project: $project_name"

    # Wait for Eclipse to be ready
    wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

    # Focus and maximize
    focus_eclipse_window

    # Dismiss any dialogs (welcome, tips)
    dismiss_dialogs 3

    # Close welcome tab if present
    close_welcome_tab

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

# Check if a Java class file exists and is valid
verify_class_file() {
    local class_file="$1"
    if [ -f "$class_file" ]; then
        # Check for Java class file magic bytes (CAFEBABE)
        local magic=$(xxd -p -l 4 "$class_file" 2>/dev/null)
        if [ "$magic" = "cafebabe" ]; then
            return 0
        fi
    fi
    return 1
}

# Get list of Java source files in a directory
list_java_files() {
    local dir="$1"
    find "$dir" -name "*.java" -type f 2>/dev/null
}

# Get list of class files in a directory
list_class_files() {
    local dir="$1"
    find "$dir" -name "*.class" -type f 2>/dev/null
}
