#!/bin/bash
# Shared utilities for RStudio tasks

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Check if RStudio is running
is_rstudio_running() {
    pgrep -f "rstudio" > /dev/null 2>&1
}

# Wait for RStudio window
wait_for_rstudio() {
    local timeout=${1:-60}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "rstudio"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Get RStudio window ID
get_rstudio_window() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "rstudio" | head -1 | awk '{print $1}'
}

# Focus RStudio window
focus_rstudio() {
    local wid=$(get_rstudio_window)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -a "$wid"
        return 0
    fi
    return 1
}

# Maximize RStudio window
maximize_rstudio() {
    local wid=$(get_rstudio_window)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz
        return 0
    fi
    return 1
}

# Run R script and capture output
run_r_script() {
    local script="$1"
    local output_file="${2:-/tmp/r_output.txt}"

    if [ -f "$script" ]; then
        R --vanilla --slave < "$script" > "$output_file" 2>&1
    else
        echo "$script" | R --vanilla --slave > "$output_file" 2>&1
    fi

    cat "$output_file"
}

# Run R expression and get result
run_r_expr() {
    local expr="$1"
    R --vanilla --slave -e "$expr" 2>/dev/null
}

# Check if R package is installed
is_package_installed() {
    local pkg="$1"
    R --vanilla --slave -e "cat(requireNamespace('$pkg', quietly=TRUE))" 2>/dev/null | grep -q "TRUE"
}

# Get list of installed packages
get_installed_packages() {
    R --vanilla --slave -e "cat(installed.packages()[,'Package'], sep='\n')" 2>/dev/null
}

# Check if file is valid R script
is_valid_r_script() {
    local file="$1"
    if [ ! -f "$file" ]; then
        return 1
    fi
    # Try to parse the file
    R --vanilla --slave -e "parse('$file')" > /dev/null 2>&1
}

# Get R version
get_r_version() {
    R --vanilla --slave -e "cat(R.version.string)" 2>/dev/null
}

# Wait for file to exist
wait_for_file() {
    local file="$1"
    local timeout=${2:-60}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if [ -f "$file" ]; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Check if file was modified after a timestamp
file_modified_after() {
    local file="$1"
    local timestamp="$2"

    if [ ! -f "$file" ]; then
        return 1
    fi

    local file_mtime=$(stat -c %Y "$file" 2>/dev/null)
    if [ "$file_mtime" -gt "$timestamp" ]; then
        return 0
    fi
    return 1
}

# Safe xdotool wrapper
safe_xdotool() {
    DISPLAY=:1 xdotool "$@" 2>/dev/null || true
}

# Type text in RStudio
type_in_rstudio() {
    local text="$1"
    focus_rstudio
    sleep 0.5
    DISPLAY=:1 xdotool type --delay 50 "$text"
}

# Press key in RStudio
press_key_rstudio() {
    local key="$1"
    focus_rstudio
    sleep 0.2
    DISPLAY=:1 xdotool key "$key"
}

# Execute R code in RStudio console (via keyboard)
execute_in_console() {
    local code="$1"
    focus_rstudio
    sleep 0.3
    # Ctrl+2 focuses the console pane in RStudio
    DISPLAY=:1 xdotool key ctrl+2
    sleep 0.3
    DISPLAY=:1 xdotool type --delay 30 "$code"
    sleep 0.2
    DISPLAY=:1 xdotool key Return
}
