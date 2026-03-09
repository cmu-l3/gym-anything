#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Seamless Loop Result ==="

TASK_NAME="configure_seamless_loop"
USER_HOME="/home/ga"
RESULT_DIR="/tmp/task_results"
TEMP_LOG="/tmp/${TASK_NAME}_export.log"

echo "[$(date)] Exporting results for: ${TASK_NAME}" | tee "${TEMP_LOG}"

# Create result directory
mkdir -p "${RESULT_DIR}"

# Export VLC configuration files
echo "[$(date)] Exporting VLC configuration..." | tee -a "${TEMP_LOG}"

# Main VLC config (vlcrc)
if [ -f "${USER_HOME}/.config/vlc/vlcrc" ]; then
    cp "${USER_HOME}/.config/vlc/vlcrc" "${RESULT_DIR}/vlcrc"
    echo "[$(date)] Exported vlcrc" | tee -a "${TEMP_LOG}"
    
    # Check for loop/repeat settings in vlcrc
    if grep -E "^(loop|repeat)=" "${USER_HOME}/.config/vlc/vlcrc" >> "${TEMP_LOG}" 2>&1; then
        echo "[$(date)] Found loop/repeat settings in vlcrc" | tee -a "${TEMP_LOG}"
    fi
else
    echo "[WARNING] vlcrc not found" | tee -a "${TEMP_LOG}"
fi

# Qt interface config (contains loop/repeat state persistence)
if [ -f "${USER_HOME}/.config/vlc/vlc-qt-interface.conf" ]; then
    cp "${USER_HOME}/.config/vlc/vlc-qt-interface.conf" "${RESULT_DIR}/vlc-qt-interface.conf"
    echo "[$(date)] Exported Qt interface config" | tee -a "${TEMP_LOG}"
    
    # Check for loop/repeat in Qt config
    if grep -iE "(loop|repeat)" "${USER_HOME}/.config/vlc/vlc-qt-interface.conf" >> "${TEMP_LOG}" 2>&1; then
        echo "[$(date)] Found loop/repeat settings in Qt config" | tee -a "${TEMP_LOG}"
    fi
else
    echo "[WARNING] Qt interface config not found" | tee -a "${TEMP_LOG}"
fi

# Export playlist file
PLAYLIST_FILE="${USER_HOME}/Videos/playlists/stream_loop.m3u"
if [ -f "${PLAYLIST_FILE}" ]; then
    cp "${PLAYLIST_FILE}" "${RESULT_DIR}/stream_loop.m3u"
    echo "[$(date)] Exported playlist file" | tee -a "${TEMP_LOG}"
    echo "[$(date)] Playlist contents:" | tee -a "${TEMP_LOG}"
    cat "${PLAYLIST_FILE}" | tee -a "${TEMP_LOG}"
else
    echo "[WARNING] Playlist file not found: ${PLAYLIST_FILE}" | tee -a "${TEMP_LOG}"
    
    # Look for any recently created playlist in the directory
    RECENT_PLAYLIST=$(find "${USER_HOME}/Videos/playlists" -name "*.m3u" -o -name "*.xspf" -type f -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_PLAYLIST" ]; then
        echo "[$(date)] Found recent playlist: ${RECENT_PLAYLIST}" | tee -a "${TEMP_LOG}"
        cp "${RECENT_PLAYLIST}" "${RESULT_DIR}/stream_loop.m3u"
    fi
fi

# Export VLC state/session files if they exist
if [ -d "${USER_HOME}/.local/share/vlc" ]; then
    mkdir -p "${RESULT_DIR}/vlc_state"
    # Copy recent files (modified in last 10 minutes)
    find "${USER_HOME}/.local/share/vlc" -type f -mmin -10 -exec cp {} "${RESULT_DIR}/vlc_state/" \; 2>/dev/null || true
    echo "[$(date)] Exported VLC state files" | tee -a "${TEMP_LOG}"
fi

# Close VLC gracefully
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
        sleep 0.5
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "[WARNING] VLC still running, force killing..." | tee -a "${TEMP_LOG}"
        kill_vlc ga || true
        sleep 1
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_seamless_loop_completed.txt
echo "Configure seamless loop task completed" >> /tmp/vlc_seamless_loop_completed.txt

# List all exported files
echo "[$(date)] Exported files:" | tee -a "${TEMP_LOG}"
ls -lah "${RESULT_DIR}/" | tee -a "${TEMP_LOG}"

if [ -f "${RESULT_DIR}/stream_loop.m3u" ]; then
    echo "[$(date)] Final playlist check:" | tee -a "${TEMP_LOG}"
    cat "${RESULT_DIR}/stream_loop.m3u" | tee -a "${TEMP_LOG}"
fi

echo "[$(date)] Export complete" | tee -a "${TEMP_LOG}"
echo "=== Export Complete ==="