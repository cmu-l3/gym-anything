#!/bin/bash
# Shared utilities for LimeSurvey tasks

# ===== Auto-check: wait for LimeSurvey web service on source =====
# This ensures Docker containers are ready after cache restore
echo "Checking LimeSurvey web service readiness..."
for _ls_check_i in $(seq 1 60); do
    _ls_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/" 2>/dev/null || echo "000")
    if [ "$_ls_code" = "200" ] || [ "$_ls_code" = "302" ]; then
        echo "LimeSurvey web service is ready"
        break
    fi
    sleep 2
done

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
    echo "Screenshot saved: $path"
}

# LimeSurvey database query
limesurvey_query() {
    local query="$1"
    docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$query" 2>/dev/null
}

# Get survey count
get_survey_count() {
    limesurvey_query "SELECT COUNT(*) FROM lime_surveys" 2>/dev/null || echo "0"
}

# Get response count for a survey
get_response_count() {
    local survey_id="$1"
    limesurvey_query "SELECT COUNT(*) FROM lime_survey_${survey_id}" 2>/dev/null || echo "0"
}

# Check if survey exists by title (case-insensitive)
survey_exists() {
    local title="$1"
    local result=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE LOWER(surveyls_title) LIKE LOWER('%${title}%') LIMIT 1")
    [ -n "$result" ] && return 0 || return 1
}

# Get survey ID by title
get_survey_id() {
    local title="$1"
    limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE LOWER(surveyls_title) LIKE LOWER('%${title}%') LIMIT 1"
}

# Get question count for a survey
get_question_count() {
    local survey_id="$1"
    limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid=${survey_id} AND parent_qid=0" 2>/dev/null || echo "0"
}

# Export JSON result safely
export_json_result() {
    local json_content="$1"
    local output_path="${2:-/tmp/task_result.json}"

    # Create temp file first
    local temp_json=$(mktemp /tmp/result.XXXXXX.json)
    echo "$json_content" > "$temp_json"

    # Move to final location with permission handling
    rm -f "$output_path" 2>/dev/null || sudo rm -f "$output_path" 2>/dev/null || true
    cp "$temp_json" "$output_path" 2>/dev/null || sudo cp "$temp_json" "$output_path"
    chmod 666 "$output_path" 2>/dev/null || sudo chmod 666 "$output_path" 2>/dev/null || true
    rm -f "$temp_json"

    echo "Result saved to: $output_path"
}

# Wait for LimeSurvey web service
wait_for_limesurvey() {
    local timeout=${1:-120}
    local elapsed=0
    echo "Waiting for LimeSurvey web service..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "LimeSurvey is ready (HTTP $HTTP_CODE) after ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: LimeSurvey not ready after ${timeout}s"
    return 1
}

# Launch Firefox with web service wait
restart_firefox() {
    local url="${1:-http://localhost/index.php/admin}"

    # Wait for LimeSurvey web service before launching Firefox
    wait_for_limesurvey 120 || echo "WARNING: LimeSurvey may not be ready"

    # Kill ALL Firefox processes aggressively (snap Firefox uses different process names)
    pkill -9 -f firefox 2>/dev/null || true
    pkill -9 -f 'snap.*firefox' 2>/dev/null || true
    pkill -9 -f 'Web Content' 2>/dev/null || true
    pkill -9 -f 'GeckoMain' 2>/dev/null || true
    killall -9 firefox firefox-bin firefox-esr 2>/dev/null || true
    sleep 5

    # Clean lock files from ALL possible Firefox locations
    find /home/ga/.mozilla/firefox/ -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/.mozilla/firefox/ -name "lock" -delete 2>/dev/null || true
    find /home/ga/snap/firefox/ -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/snap/firefox/ -name "lock" -delete 2>/dev/null || true
    find /tmp/ -name ".parentlock" -delete 2>/dev/null || true

    # Use setsid (matching proven rancher_env pattern) — no --new-instance or -profile flags
    su - ga -c "DISPLAY=:1 setsid firefox '$url' > /tmp/firefox.log 2>&1 &"

    # Wait for Firefox window (snap Firefox takes longer to initialize)
    sleep 10
    local elapsed=0
    while [ $elapsed -lt 30 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|limesurvey"; then
            echo "Firefox window detected"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    # Maximize Firefox
    sleep 1
    local wid
    wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
    sleep 2
}

# Focus Firefox window
focus_firefox() {
    DISPLAY=:1 wmctrl -a Firefox 2>/dev/null || \
    DISPLAY=:1 wmctrl -a Mozilla 2>/dev/null || \
    DISPLAY=:1 wmctrl -a limesurvey 2>/dev/null || true
}

# Wait for page load (checks for URL change)
wait_for_page_load() {
    local timeout="${1:-10}"
    sleep "$timeout"
}
