#!/bin/bash
# Shared utilities for Portfolio Performance tasks

# Ensure X11 auth works when running as root via sudo
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Screenshot function using ImageMagick (more reliable than scrot)
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    import -window root "$path" 2>/dev/null || \
    scrot "$path" 2>/dev/null || true
}

# Wait for Portfolio Performance window
wait_for_pp_window() {
    local timeout=${1:-60}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if wmctrl -l 2>/dev/null | grep -qi "Portfolio Performance\|PortfolioPerformance\|unnamed"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "Portfolio Performance window not found after ${timeout}s"
    return 1
}

# Find Portfolio Performance XML files in user directory
find_pp_files() {
    find /home/ga -name "*.xml" -newer /tmp/task_start_marker 2>/dev/null | head -20
    find /home/ga -name "*.portfolio" -newer /tmp/task_start_marker 2>/dev/null | head -20
}

# List all Portfolio Performance data files
list_pp_data() {
    find /home/ga -name "*.xml" -o -name "*.portfolio" 2>/dev/null | head -20
}

# Parse PP XML file for securities count (uses Python to avoid matching <security reference="..."/>)
count_securities_in_xml() {
    local xml_file="$1"
    if [ -f "$xml_file" ]; then
        python3 -c "
import xml.etree.ElementTree as ET
try:
    root = ET.parse('$xml_file').getroot()
    se = root.find('securities')
    print(len(se.findall('security')) if se is not None else 0)
except: print(0)
" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Parse PP XML file for transaction count
count_transactions_in_xml() {
    local xml_file="$1"
    local count=0
    if [ -f "$xml_file" ]; then
        count=$(grep -c "<account-transaction>" "$xml_file" 2>/dev/null || true)
    fi
    echo "${count:-0}"
}

# Parse PP XML file for portfolio-transaction count (buy/sell)
count_portfolio_transactions_in_xml() {
    local xml_file="$1"
    local count=0
    if [ -f "$xml_file" ]; then
        count=$(grep -c "<portfolio-transaction>" "$xml_file" 2>/dev/null || true)
    fi
    echo "${count:-0}"
}

# Check if a file was modified after a timestamp
file_modified_after() {
    local file="$1"
    local marker="$2"
    if [ -f "$file" ] && [ -f "$marker" ]; then
        if [ "$file" -nt "$marker" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

# Get the most recently modified PP file
get_latest_pp_file() {
    local dir="${1:-/home/ga}"
    find "$dir" \( -name "*.xml" -o -name "*.portfolio" \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}'
}

# JSON escape a string
json_escape() {
    local str="$1"
    echo "$str" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))"
}

# Create task start marker
mark_task_start() {
    touch /tmp/task_start_marker
    date -Iseconds > /tmp/task_start_time
}

# Clean up leftover files from other tasks to prevent cross-contamination
# Each task creates its own specific XML; remove others
clean_portfolio_data() {
    local keep_file="$1"  # File to keep (basename), empty to remove all
    local data_dir="/home/ga/Documents/PortfolioData"
    mkdir -p "$data_dir"
    if [ -n "$keep_file" ]; then
        # Remove all XML/CSV files except the one we're keeping
        find "$data_dir" -maxdepth 1 \( -name "*.xml" -o -name "*.csv" -o -name "*.portfolio" \) \
            ! -name "$keep_file" -delete 2>/dev/null || true
    else
        # Remove all data files (for create_portfolio which starts fresh)
        find "$data_dir" -maxdepth 1 \( -name "*.xml" -o -name "*.csv" -o -name "*.portfolio" \) \
            -delete 2>/dev/null || true
    fi
    chown -R ga:ga "$data_dir" 2>/dev/null || true
}

# Open a portfolio file in the already-running PP via Ctrl+O
# PP ignores command-line file arguments - always shows Welcome page
# Must use Ctrl+O > Ctrl+L > type path > Enter to open files
open_file_in_pp() {
    local filepath="$1"
    local max_wait="${2:-10}"

    # Click in PP body to ensure focus
    xdotool mousemove 960 540 click 1 2>/dev/null || true
    sleep 1

    # Open file dialog with Ctrl+O
    xdotool key ctrl+o 2>/dev/null || true
    sleep 2

    # Enter path mode with Ctrl+L
    xdotool key ctrl+l 2>/dev/null || true
    sleep 0.5

    # Type the file path
    xdotool type --delay 20 "$filepath" 2>/dev/null || true
    sleep 0.5

    # Press Enter to open
    xdotool key Return 2>/dev/null || true
    sleep 3

    # Wait for file tab to appear (check window title changes)
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if wmctrl -l 2>/dev/null | grep -qi "$(basename "$filepath" .xml)"; then
            echo "File loaded: $filepath"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "File may have loaded (tab not confirmed in title)"
    return 0
}
