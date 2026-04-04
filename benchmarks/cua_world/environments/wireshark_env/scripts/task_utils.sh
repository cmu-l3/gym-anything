#!/bin/bash
# Shared utilities for all Wireshark tasks

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Safe JSON write: temp file first, then move with permission handling
safe_json_write() {
    local json_content="$1"
    local target_path="$2"

    TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
    echo "$json_content" > "$TEMP_JSON"

    rm -f "$target_path" 2>/dev/null || sudo rm -f "$target_path" 2>/dev/null || true
    cp "$TEMP_JSON" "$target_path" 2>/dev/null || sudo cp "$TEMP_JSON" "$target_path"
    chmod 666 "$target_path" 2>/dev/null || sudo chmod 666 "$target_path" 2>/dev/null || true
    rm -f "$TEMP_JSON"
}

# Get packet count from a PCAP file
get_packet_count() {
    local pcap_file="$1"
    tshark -r "$pcap_file" 2>/dev/null | wc -l
}

# Get filtered packet count
get_filtered_count() {
    local pcap_file="$1"
    local filter="$2"
    tshark -r "$pcap_file" -Y "$filter" 2>/dev/null | wc -l
}

# Extract field values from PCAP
extract_fields() {
    local pcap_file="$1"
    local filter="$2"
    local fields="$3"
    tshark -r "$pcap_file" -Y "$filter" -T fields -e "$fields" 2>/dev/null
}

# Check if Wireshark is running
is_wireshark_running() {
    pgrep -c wireshark 2>/dev/null || echo "0"
}
