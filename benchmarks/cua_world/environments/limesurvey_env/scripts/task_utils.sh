#!/bin/bash
# Shared utilities for LimeSurvey tasks

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
