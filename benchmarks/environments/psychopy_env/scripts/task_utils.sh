#!/bin/bash
# Shared utilities for PsychoPy tasks

# Take screenshot using ImageMagick (more reliable than scrot in VNC)
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# Check if PsychoPy is running
is_psychopy_running() {
    pgrep -f "psychopy" > /dev/null 2>&1
}

# Wait for PsychoPy window to appear
wait_for_psychopy() {
    local timeout=${1:-60}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "psychopy\|builder\|coder"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Get PsychoPy Builder window ID (prefer Builder over Runner/Coder)
get_builder_window() {
    # Try Builder first (most tasks need it)
    local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "builder" | head -1 | awk '{print $1}')
    if [ -n "$wid" ]; then
        echo "$wid"
        return 0
    fi
    # Fallback to any PsychoPy window
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "psychopy\|coder" | head -1 | awk '{print $1}'
}

# Get PsychoPy Coder window ID
get_coder_window() {
    local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "coder" | head -1 | awk '{print $1}')
    if [ -n "$wid" ]; then
        echo "$wid"
        return 0
    fi
    # Fallback to any PsychoPy window
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "psychopy\|builder" | head -1 | awk '{print $1}'
}

# Get any PsychoPy window ID (legacy compat)
get_psychopy_window() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "psychopy\|builder\|coder" | head -1 | awk '{print $1}'
}

# Focus PsychoPy Builder window specifically
focus_builder() {
    local wid=$(get_builder_window)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -a "$wid"
        return 0
    fi
    return 1
}

# Focus PsychoPy Coder window specifically
focus_coder() {
    local wid=$(get_coder_window)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -a "$wid"
        return 0
    fi
    return 1
}

# Focus any PsychoPy window (legacy compat)
focus_psychopy() {
    local wid=$(get_psychopy_window)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -a "$wid"
        return 0
    fi
    return 1
}

# Maximize a specific window by ID
maximize_window() {
    local wid="$1"
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz
        return 0
    fi
    return 1
}

# Maximize PsychoPy window
maximize_psychopy() {
    local wid=$(get_psychopy_window)
    maximize_window "$wid"
}

# Dismiss PsychoPy startup dialogs
dismiss_psychopy_dialogs() {
    DISPLAY=:1 wmctrl -c 'PsychoPy Error' 2>/dev/null || true
    DISPLAY=:1 wmctrl -c 'Additional configuration' 2>/dev/null || true
    DISPLAY=:1 wmctrl -c 'Changes in' 2>/dev/null || true
    DISPLAY=:1 wmctrl -c 'Tip of the Day' 2>/dev/null || true
}

# Check if file is valid .psyexp XML
is_valid_psyexp() {
    local file="$1"
    if [ ! -f "$file" ]; then
        return 1
    fi
    grep -q "<PsychoPy2experiment" "$file" 2>/dev/null || \
    grep -q "psychopy" "$file" 2>/dev/null
}

# Check if .psyexp contains a specific routine
psyexp_has_routine() {
    local file="$1"
    local routine="$2"
    grep -qi "name=\"${routine}\"" "$file" 2>/dev/null
}

# Check if .psyexp has a loop element
psyexp_has_loop() {
    local file="$1"
    grep -qi "LoopInitiator\|LoopTerminator\|<Param name=\"nReps\"" "$file" 2>/dev/null
}

# Check if experiment data was generated
has_experiment_data() {
    local data_dir="${1:-/home/ga/PsychoPyExperiments/data}"
    [ -d "$data_dir" ] && [ -n "$(ls -A "$data_dir" 2>/dev/null)" ]
}

# Record task start time
record_task_start() {
    date +%s > /home/ga/.task_start_time
}

# Get task start time
get_task_start() {
    cat /home/ga/.task_start_time 2>/dev/null || echo "0"
}

# Generate a random nonce for result integrity verification
generate_nonce() {
    local nonce=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    echo "$nonce" > /home/ga/.task_nonce
    chmod 600 /home/ga/.task_nonce 2>/dev/null || true
    echo "$nonce"
}

# Get the nonce generated during task setup
get_nonce() {
    cat /home/ga/.task_nonce 2>/dev/null || echo ""
}

# Check if file was modified after task start
was_modified_after_start() {
    local file="$1"
    local start_time=$(get_task_start)
    if [ ! -f "$file" ]; then
        return 1
    fi
    local file_mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
    [ "$file_mtime" -gt "$start_time" ]
}

# Safe JSON write to /tmp with permission handling
write_result_json() {
    local json_content="$1"
    local target="${2:-/tmp/task_result.json}"

    local temp_json=$(mktemp /tmp/result.XXXXXX.json)
    echo "$json_content" > "$temp_json"

    rm -f "$target" 2>/dev/null || sudo rm -f "$target" 2>/dev/null || true
    cp "$temp_json" "$target" 2>/dev/null || sudo cp "$temp_json" "$target"
    chmod 666 "$target" 2>/dev/null || sudo chmod 666 "$target" 2>/dev/null || true
    rm -f "$temp_json"
}
