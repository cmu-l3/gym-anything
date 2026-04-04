#!/bin/bash
# Shared utilities for ActivInspire tasks

# Take a screenshot and save to specified path
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Wait for ActivInspire to be ready
wait_for_activinspire() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "activinspire\|Inspire" > /dev/null 2>&1; then
            echo "ActivInspire is running"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: ActivInspire not detected within ${timeout}s"
    return 1
}

# Launch ActivInspire if not running
ensure_activinspire_running() {
    if ! pgrep -f "activinspire\|Inspire" > /dev/null 2>&1; then
        echo "Starting ActivInspire..."
        su - ga -c "DISPLAY=:1 /home/ga/Desktop/launch_activinspire.sh &" 2>/dev/null || true
        sleep 5
        wait_for_activinspire 30
    fi
}

# Focus the ActivInspire window
focus_activinspire() {
    # Try to focus using wmctrl
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
