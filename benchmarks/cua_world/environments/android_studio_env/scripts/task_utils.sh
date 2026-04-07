#!/bin/bash
# Shared utilities for all Android Studio tasks

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Wait for Android Studio window to appear
wait_for_android_studio() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "android\|studio"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Wait for Android Studio to fully load a project (window title contains project name)
wait_for_project_loaded() {
    local project_name="${1:-}"
    local timeout="${2:-120}"
    local elapsed=0

    echo "Waiting for Android Studio to load project: $project_name"

    while [ $elapsed -lt $timeout ]; do
        if [ -n "$project_name" ]; then
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$project_name"; then
                echo "Project window detected after ${elapsed}s"
                sleep 5
                return 0
            fi
        else
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "android\|studio" | grep -v -qi "welcome"; then
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

# Dismiss any dialogs that might appear
dismiss_dialogs() {
    local max_attempts="${1:-5}"
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 1
        attempt=$((attempt + 1))
    done
}

# Handle Trust Project dialog
handle_trust_dialog() {
    local max_attempts="${1:-10}"
    local attempt=0

    echo "Checking for Trust Project dialog..."

    while [ $attempt -lt $max_attempts ]; do
        local dialog_visible=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "trust" || true)

        if [ -n "$dialog_visible" ]; then
            echo "Trust dialog detected, clicking Trust Project button..."
            local trust_wid=$(DISPLAY=:1 wmctrl -l | grep -i "trust" | head -1 | awk '{print $1}')
            if [ -n "$trust_wid" ]; then
                DISPLAY=:1 wmctrl -ia "$trust_wid" 2>/dev/null || true
            fi
            sleep 0.5
            DISPLAY=:1 xdotool key Tab 2>/dev/null || true
            sleep 0.3
            DISPLAY=:1 xdotool key Return 2>/dev/null || true
            sleep 2

            if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "trust"; then
                echo "Trust dialog dismissed successfully"
                return 0
            fi
        else
            echo "No Trust dialog detected"
            return 0
        fi

        sleep 2
        attempt=$((attempt + 1))
    done

    echo "WARNING: Could not dismiss Trust dialog after $max_attempts attempts"
    return 1
}

# Focus and maximize Android Studio window
focus_android_studio_window() {
    local WID=$(DISPLAY=:1 wmctrl -l | grep -i "android\|studio" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "Android Studio window focused and maximized"
        return 0
    fi
    return 1
}

# Open a project in Android Studio (with retry logic for reliability)
setup_android_studio_project() {
    local project_path="$1"
    local project_name="${2:-$(basename $project_path)}"
    local timeout="${3:-120}"
    local max_retries=3
    local attempt=0

    echo "Opening project: $project_path"

    # Ensure local.properties with sdk.dir exists so Gradle can find the SDK
    if [ -d "$project_path" ]; then
        echo "sdk.dir=/opt/android-sdk" > "$project_path/local.properties"
        chown ga:ga "$project_path/local.properties" 2>/dev/null || true
        echo "  Wrote local.properties with sdk.dir"
    fi

    # Kill any existing Android Studio to avoid IPC race conditions
    # The "Cannot Execute Command" error occurs when studio.sh sends an IPC
    # command to an already-running instance and it fails
    echo "Stopping any existing Android Studio instances..."
    pkill -f "studio" 2>/dev/null || true
    pkill -f "idea" 2>/dev/null || true
    sleep 5
    # Force kill if still running
    pkill -9 -f "studio" 2>/dev/null || true
    pkill -9 -f "idea" 2>/dev/null || true
    sleep 3

    while [ $attempt -lt $max_retries ]; do
        attempt=$((attempt + 1))
        echo "=== Attempt $attempt of $max_retries to open project ==="

        # Launch Android Studio with the project
        su - ga -c "export DISPLAY=:1; export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; export ANDROID_HOME=/opt/android-sdk; /opt/android-studio/bin/studio.sh '$project_path' > /tmp/android_studio_task.log 2>&1 &"

        # Initial wait for IDE to start
        sleep 15

        # Check for and dismiss error dialogs
        _dismiss_error_dialogs

        # Handle Trust Project dialog
        handle_trust_dialog 5

        # Wait for project to load
        if wait_for_project_loaded "$project_name" "$timeout"; then
            echo "Project window detected successfully"

            # Check for error dialogs again
            _dismiss_error_dialogs

            # Handle Trust dialog again
            handle_trust_dialog 3

            # Dismiss other dialogs (tip-of-day, What's New, etc.)
            dismiss_dialogs 3

            # Focus and maximize
            focus_android_studio_window

            # Verify the project window title contains the project name
            sleep 2
            local project_visible=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "$project_name" || true)
            if [ -n "$project_visible" ]; then
                echo "Project '$project_name' confirmed open in Android Studio"
                sleep 3
                echo "Project setup complete"
                return 0
            fi

            # Even without exact name match, a non-Welcome Studio window is acceptable
            local any_studio=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "android\|studio" | grep -v -i "welcome" || true)
            if [ -n "$any_studio" ]; then
                echo "Android Studio project window found: $any_studio"
                sleep 3
                echo "Project setup complete"
                return 0
            fi
        fi

        echo "Attempt $attempt: project window not confirmed"

        if [ $attempt -lt $max_retries ]; then
            echo "Killing Android Studio and retrying..."
            pkill -f "studio" 2>/dev/null || true
            pkill -f "idea" 2>/dev/null || true
            sleep 5
            pkill -9 -f "studio" 2>/dev/null || true
            pkill -9 -f "idea" 2>/dev/null || true
            sleep 3
        fi
    done

    echo "WARNING: Project may not have opened after $max_retries attempts"
    # Final attempt to focus whatever is open
    focus_android_studio_window 2>/dev/null || true
    sleep 3
    echo "Project setup complete (with warnings)"
}

# Dismiss error dialogs (Cannot Execute Command, Opening was cancelled, etc.)
_dismiss_error_dialogs() {
    local error_dialog=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "cannot|error|cancel" || true)
    if [ -n "$error_dialog" ]; then
        echo "Error dialog detected: $error_dialog"
        # Try to focus and dismiss it
        local err_wid=$(echo "$error_dialog" | head -1 | awk '{print $1}')
        if [ -n "$err_wid" ]; then
            DISPLAY=:1 wmctrl -ia "$err_wid" 2>/dev/null || true
            sleep 0.5
        fi
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 1
    fi
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

# Run Gradle in a project directory
run_gradle() {
    local project_dir="$1"
    local task="${2:-assembleDebug}"
    local output_file="${3:-/tmp/gradle_output.log}"

    cd "$project_dir" && \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew "$task" --no-daemon > "$output_file" 2>&1
    return $?
}
