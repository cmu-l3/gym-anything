#!/bin/bash
# Shared utilities for VistA tasks (YDBGui web interface version)

# Screenshot function (uses ImageMagick import as scrot may not be installed)
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# VistA database query via Docker container (YottaDB syntax)
vista_query() {
    local query="$1"
    docker exec -u vehu vista-vehu bash -c "source /home/vehu/etc/env && yottadb -run %XCMD '$query'" 2>/dev/null
}

# Get patient count from VistA
get_patient_count() {
    # Count entries in ^DPT (Patient file #2)
    docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S C=0,X=0 F  S X=\$O(^DPT(X)) Q:X=\"\"  S C=C+1 S:C>9999 X=\"\" W:X=\"\" C"' 2>/dev/null | tail -1
}

# Get vitals count from VistA
get_vitals_count() {
    # Count entries in ^GMR(120.5) (Vitals/Measurements file)
    docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S C=0,X=0 F  S X=\$O(^GMR(120.5,X)) Q:X=\"\"  S C=C+1 S:C>999 X=\"\" W:X=\"\" C"' 2>/dev/null | tail -1
}

# List patients from VistA
list_patients() {
    local count="${1:-10}"
    docker exec -u vehu vista-vehu bash -c "source /home/vehu/etc/env && yottadb -run %XCMD 'S U=\"^\",X=0,N=0 F  S X=\\\$O(^DPT(X)) Q:X=\"\"!(N>=$count)  S N=N+1,NM=\\\$P(\\\$G(^DPT(X,0)),U,1) W N,\" DFN:\",X,\" \",NM,!'" 2>/dev/null
}

# Get patient data by DFN
get_patient_data() {
    local dfn="$1"
    docker exec -u vehu vista-vehu bash -c "source /home/vehu/etc/env && yottadb -run %XCMD 'S U=\"^\",DFN=$dfn W \\\$P(\\\$G(^DPT(DFN,0)),U,1),\"|\",\\\$P(\\\$G(^DPT(DFN,0)),U,3),\"|\",\\\$P(\\\$G(^DPT(DFN,0)),U,9)'" 2>/dev/null | tail -1
}

# Check if VistA container is running
check_vista_running() {
    docker ps --filter "name=vista-vehu" --filter "status=running" -q 2>/dev/null | head -1
}

# Get VistA container status
vista_status() {
    docker ps -a --filter "name=vista-vehu" --format "{{.Status}}"
}

# Get container IP address
get_container_ip() {
    docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null
}

# Check if YDBGui is accessible
check_ydbgui() {
    local container_ip="${1:-$(get_container_ip)}"
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://${container_ip}:8089/" 2>/dev/null)
    [ "$http_code" = "200" ]
}

# Focus Firefox window
focus_firefox_window() {
    local wid=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|ydbgui\|yottadb" | head -1 | awk '{print $1}')
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null
        return 0
    fi
    return 1
}

# Check if Firefox window exists
firefox_window_exists() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|ydbgui\|yottadb"
}

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g; s/\r/\\r/g'
}

# Safe JSON write using temp file pattern
write_json_result() {
    local content="$1"
    local output_path="$2"

    local temp_json=$(mktemp /tmp/result.XXXXXX.json)
    echo "$content" > "$temp_json"

    # Remove old file and copy new one (with sudo fallback)
    rm -f "$output_path" 2>/dev/null || sudo rm -f "$output_path" 2>/dev/null || true
    cp "$temp_json" "$output_path" 2>/dev/null || sudo cp "$temp_json" "$output_path"
    chmod 666 "$output_path" 2>/dev/null || sudo chmod 666 "$output_path" 2>/dev/null || true
    rm -f "$temp_json"
}
