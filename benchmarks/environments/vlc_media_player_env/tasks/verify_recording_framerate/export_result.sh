#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Recording Framerate Result ==="

USER_HOME="/home/ga"
VIDEOS_DIR="${USER_HOME}/Videos"
OUTPUT_DIR="/tmp/task_output"

log_export() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a /tmp/vlc_task_verify_recording.log
}

log_export "Exporting verify_recording_framerate results..."

mkdir -p "${OUTPUT_DIR}"
chown -R ga:ga "${OUTPUT_DIR}"

# Look for analysis files the agent might have created
# Common naming patterns: recording_analysis.txt, framerate_analysis.txt, etc.

ANALYSIS_FOUND="false"

# Priority 1: Expected filenames in Videos directory
for filename in "recording_analysis.txt" "framerate_analysis.txt" "frame_report.txt" \
                "codec_info.txt" "media_info.txt" "analysis.txt"; do
    if [ -f "${VIDEOS_DIR}/${filename}" ]; then
        cp "${VIDEOS_DIR}/${filename}" "${OUTPUT_DIR}/"
        log_export "Found analysis file: ${filename}"
        ANALYSIS_FOUND="true"
    fi
done

# Priority 2: Any .txt or .log files created in last 5 minutes in Videos directory
if [ "$ANALYSIS_FOUND" = "false" ]; then
    log_export "Looking for recent text files in Videos directory..."
    find "${VIDEOS_DIR}" -maxdepth 1 -type f \( -name "*.txt" -o -name "*.log" \) -mmin -5 2>/dev/null | while read -r file; do
        if [ -f "$file" ]; then
            cp "$file" "${OUTPUT_DIR}/"
            log_export "Found recent file: $(basename $file)"
            ANALYSIS_FOUND="true"
        fi
    done
fi

# Priority 3: Check home directory for analysis files
if [ "$ANALYSIS_FOUND" = "false" ]; then
    log_export "Looking for analysis files in home directory..."
    find "${USER_HOME}" -maxdepth 1 -type f \( -name "*recording*.txt" -o -name "*framerate*.txt" -o -name "*analysis*.txt" \) -mmin -5 2>/dev/null | while read -r file; do
        if [ -f "$file" ]; then
            cp "$file" "${OUTPUT_DIR}/"
            log_export "Found file in home: $(basename $file)"
            ANALYSIS_FOUND="true"
        fi
    done
fi

# Priority 4: Check if VLC message log was saved
VLC_CACHE="${USER_HOME}/.cache/vlc"
if [ -f "${VLC_CACHE}/vlc-log.txt" ]; then
    cp "${VLC_CACHE}/vlc-log.txt" "${OUTPUT_DIR}/"
    log_export "Found VLC log"
    ANALYSIS_FOUND="true"
fi

# Check VLC messages if available
if [ -f "/tmp/vlc_messages.log" ]; then
    cp "/tmp/vlc_messages.log" "${OUTPUT_DIR}/"
    log_export "Found VLC messages log"
    ANALYSIS_FOUND="true"
fi

# Copy VLC config (might show enabled diagnostic features)
if [ -f "${USER_HOME}/.config/vlc/vlcrc" ]; then
    cp "${USER_HOME}/.config/vlc/vlcrc" "${OUTPUT_DIR}/"
    log_export "Copied VLC config"
fi

# Copy the original recording for verification
if [ -f "${VIDEOS_DIR}/gameplay_recording.mp4" ]; then
    cp "${VIDEOS_DIR}/gameplay_recording.mp4" "${OUTPUT_DIR}/"
    log_export "Copied original recording"
fi

# Copy ground truth
if [ -f "/tmp/recording_ground_truth.json" ]; then
    cp /tmp/recording_ground_truth.json "${OUTPUT_DIR}/"
    log_export "Copied ground truth"
fi

# Close VLC gracefully
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    log_export "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Fallback: force kill if still running
if is_vlc_running; then
    log_export "VLC still running, force killing..."
    kill_vlc ga
fi

# Create completion marker
echo "$(date)" > "${OUTPUT_DIR}/vlc_framerate_completed.txt"
echo "Analysis files found: ${ANALYSIS_FOUND}" >> "${OUTPUT_DIR}/vlc_framerate_completed.txt"

log_export "Export complete. Files in ${OUTPUT_DIR}:"
ls -lh "${OUTPUT_DIR}/" 2>/dev/null || log_export "Output directory is empty or inaccessible"

echo "=== Export Complete ==="