#!/bin/bash
# Shared utilities for all OpenCAD tasks

# Database query via Docker MySQL
opencad_db_query() {
    local query="$1"
    docker exec opencad-db mysql -u opencad -popencadpass opencad -N -e "$query" 2>/dev/null
}

# Take screenshot using ImageMagick (more reliable than scrot)
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# Get count of records in a table
get_table_count() {
    local table="$1"
    local where_clause="${2:-1=1}"
    opencad_db_query "SELECT COUNT(*) FROM ${table} WHERE ${where_clause}"
}

# Get call count
get_call_count() {
    opencad_db_query "SELECT COUNT(*) FROM calls"
}

# Get active call count (calls table = active, call_history = closed)
get_active_call_count() {
    opencad_db_query "SELECT COUNT(*) FROM calls"
}

# Get civilian count (use ncic_names - actual person records, not junction table)
get_civilian_count() {
    opencad_db_query "SELECT COUNT(*) FROM ncic_names"
}

# Get BOLO vehicle count
get_bolo_vehicle_count() {
    opencad_db_query "SELECT COUNT(*) FROM bolos_vehicles"
}

# Get BOLO person count
get_bolo_person_count() {
    opencad_db_query "SELECT COUNT(*) FROM bolos_persons"
}

# Get user count
get_user_count() {
    opencad_db_query "SELECT COUNT(*) FROM users"
}

# Get pending user count
get_pending_user_count() {
    opencad_db_query "SELECT COUNT(*) FROM users WHERE approved = 0"
}

# Get approved user count
get_approved_user_count() {
    opencad_db_query "SELECT COUNT(*) FROM users WHERE approved = 1"
}

# Get NCIC name count
get_ncic_name_count() {
    opencad_db_query "SELECT COUNT(*) FROM ncic_names"
}

# Check if a civilian exists by name (case-insensitive)
# In OpenCAD, civilian_names is a junction table (user_id, names_id).
# Actual name data is in ncic_names.name (single field).
civilian_exists() {
    local full_name="$1"
    local result
    result=$(opencad_db_query "SELECT id FROM ncic_names WHERE LOWER(TRIM(name)) LIKE LOWER(TRIM('%${full_name}%')) LIMIT 1")
    [ -n "$result" ] && return 0 || return 1
}

# JSON-safe string escaping
json_escape() {
    local str="$1"
    echo "$str" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ' | head -c 5000
}

# Safe write result JSON with permission handling
safe_write_result() {
    local json_content="$1"
    local output_path="${2:-/tmp/task_result.json}"

    local temp_json
    temp_json=$(mktemp /tmp/result.XXXXXX.json)
    echo "$json_content" > "$temp_json"

    rm -f "$output_path" 2>/dev/null || sudo rm -f "$output_path" 2>/dev/null || true
    cp "$temp_json" "$output_path" 2>/dev/null || sudo cp "$temp_json" "$output_path"
    chmod 666 "$output_path" 2>/dev/null || sudo chmod 666 "$output_path" 2>/dev/null || true
    rm -f "$temp_json"
}
