#!/bin/bash
# Shared utilities for ActivInspire tasks

# Take a screenshot and save to specified path
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

activinspire_window_open() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -Eq \
        "ActivInspire|Welcome to ActivInspire|Promethean License Agreement"
}

wait_for_session_bus() {
    local runtime_dir="/run/user/$(id -u ga)"
    local timeout="${1:-60}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if [ -S "$runtime_dir/bus" ]; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

is_supported_focal_base() {
    . /etc/os-release
    [ "${VERSION_CODENAME:-}" = "focal" ]
}

get_display_dimensions() {
    local dims
    dims=$(DISPLAY=:1 xdpyinfo 2>/dev/null | awk '/dimensions:/{print $2; exit}')
    if [ -z "$dims" ]; then
        echo "1920 1080"
        return
    fi
    echo "${dims%x*} ${dims#*x}"
}

click_scaled_coord() {
    local base_x="$1"
    local base_y="$2"
    local width height
    read -r width height < <(get_display_dimensions)
    local click_x=$((base_x * width / 1920))
    local click_y=$((base_y * height / 1080))
    DISPLAY=:1 xdotool mousemove --sync "$click_x" "$click_y" click 1
}

focus_window_title() {
    DISPLAY=:1 wmctrl -a "$1" 2>/dev/null || true
    sleep 1
}

handle_license_dialog() {
    local timeout="${1:-30}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -q "Promethean License Agreement"; then
            focus_window_title "Promethean License Agreement"
            click_scaled_coord 788 719
            sleep 1
            click_scaled_coord 845 744
            sleep 2
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

handle_welcome_dialog() {
    local timeout="${1:-30}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -q "Welcome to ActivInspire"; then
            focus_window_title "Welcome to ActivInspire"
            click_scaled_coord 1142 587
            sleep 2
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

auto_advance_startup_dialogs() {
    if ! is_supported_focal_base; then
        return 0
    fi
    handle_license_dialog 45 || true
    handle_welcome_dialog 45 || true
}

launch_activinspire() {
    local runtime_dir="/run/user/$(id -u ga)"
    sudo -u ga bash -lc \
        "pkill -x Inspire 2>/dev/null || true
            pkill -x QtWebEngineProcess 2>/dev/null || true
            sleep 1
            nohup env \
            DISPLAY=:1 \
            XAUTHORITY=/home/ga/.Xauthority \
            XDG_RUNTIME_DIR=$runtime_dir \
            DBUS_SESSION_BUS_ADDRESS=unix:path=$runtime_dir/bus \
            DESKTOP_SESSION=ubuntu \
            LIBGL_ALWAYS_SOFTWARE=1 \
            QT_QUICK_BACKEND=software \
            QT_OPENGL=software \
            QTWEBENGINE_CHROMIUM_FLAGS=--disable-gpu \
            /usr/local/bin/activinspire \
            >/tmp/activinspire_task_launch.log 2>&1 </dev/null &"
}

# Wait for ActivInspire to be ready
wait_for_activinspire() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if activinspire_window_open; then
            echo "ActivInspire window is visible"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: ActivInspire window not detected within ${timeout}s"
    return 1
}

# Launch ActivInspire if not running
ensure_activinspire_running() {
    if ! activinspire_window_open; then
        echo "Starting ActivInspire..."
        wait_for_session_bus 60 || true
        launch_attempt=1
        while [ "$launch_attempt" -le 2 ]; do
            launch_activinspire
            if wait_for_activinspire 120; then
                auto_advance_startup_dialogs
                return 0
            fi
            echo "Retrying ActivInspire launch (attempt $((launch_attempt + 1)))..."
            launch_attempt=$((launch_attempt + 1))
        done
        return 1
    fi
    auto_advance_startup_dialogs
}

# Focus the ActivInspire window
focus_activinspire() {
    # Try to focus using wmctrl
    DISPLAY=:1 wmctrl -a "Welcome to ActivInspire" 2>/dev/null || \
    DISPLAY=:1 wmctrl -a "Promethean License Agreement" 2>/dev/null || \
    DISPLAY=:1 wmctrl -a "ActivInspire" 2>/dev/null || \
    DISPLAY=:1 wmctrl -a "Inspire" 2>/dev/null || \
    DISPLAY=:1 wmctrl -a "flipchart" 2>/dev/null || true
    sleep 0.5
}

# Check if a flipchart file exists and is valid
check_flipchart_file() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        # Flipchart files are actually ZIP archives containing XML
        local filetype=$(file -b "$filepath" 2>/dev/null)
        if echo "$filetype" | grep -qi "zip\|archive" ; then
            echo "valid"
            return 0
        elif echo "$filetype" | grep -qi "XML\|text" ; then
            # Some versions may store as plain XML
            echo "valid"
            return 0
        fi
    fi
    echo "invalid"
    return 1
}

# Extract metadata from a flipchart file
extract_flipchart_metadata() {
    local filepath="$1"
    local temp_dir=$(mktemp -d)

    if unzip -q "$filepath" -d "$temp_dir" 2>/dev/null; then
        # Look for content.xml or similar
        if [ -f "$temp_dir/content.xml" ]; then
            cat "$temp_dir/content.xml"
        elif [ -f "$temp_dir/flipchart.xml" ]; then
            cat "$temp_dir/flipchart.xml"
        fi
    fi

    rm -rf "$temp_dir"
}

# Get page count from flipchart
get_flipchart_page_count() {
    local filepath="$1"
    local temp_dir=$(mktemp -d)
    local count=0

    if unzip -q "$filepath" -d "$temp_dir" 2>/dev/null; then
        # Count page directories or XML entries
        count=$(find "$temp_dir" -name "page*.xml" -o -name "Page*" -type d 2>/dev/null | wc -l)
        if [ "$count" -eq 0 ]; then
            # Try counting from main XML
            local xml_file=$(find "$temp_dir" -name "*.xml" -type f 2>/dev/null | head -1)
            if [ -f "$xml_file" ]; then
                count=$(grep -c "<page\|<Page" "$xml_file" 2>/dev/null || echo "1")
            fi
        fi
    fi

    rm -rf "$temp_dir"
    echo "${count:-1}"
}

# Convert a shell boolean string to JSON boolean
# Usage: json_bool "true" -> true, json_bool "false" -> false, json_bool "" -> false
json_bool() {
    local val="$1"
    case "${val,,}" in
        true|yes|1) echo "true" ;;
        *) echo "false" ;;
    esac
}

# Create JSON result file safely
create_result_json() {
    local temp_file=$(mktemp /tmp/result.XXXXXX.json)
    cat > "$temp_file"
    rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
    cp "$temp_file" /tmp/task_result.json 2>/dev/null || sudo cp "$temp_file" /tmp/task_result.json
    chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
    rm -f "$temp_file"
}

# List all flipchart files in a directory
list_flipcharts() {
    local dir="${1:-/home/ga/Documents/Flipcharts}"
    find "$dir" -type f \( -name "*.flipchart" -o -name "*.flp" \) 2>/dev/null
}

# Get file modification time
get_file_mtime() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        stat -c %Y "$filepath" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get file size in bytes
get_file_size() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        stat -c %s "$filepath" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}
