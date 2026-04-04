#!/bin/bash
# Shared utilities for InVesalius tasks

take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

wait_for_invesalius() {
    local timeout=${1:-60}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        # First-run Flatpak builds can show a "Language selection" dialog before the
        # main "InVesalius" window appears. Dismiss it to make startup deterministic.
        if DISPLAY=:1 wmctrl -l | grep -qi "Language selection"; then
            dismiss_language_selection_dialog || true
        fi

        if DISPLAY=:1 wmctrl -l | grep -qi "InVesalius"; then
            echo "InVesalius window detected"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "InVesalius window timeout"
    return 1
}

get_window_id_by_title() {
    # Return the first window id whose title matches the given (regex) pattern.
    local pattern="$1"
    DISPLAY=:1 wmctrl -l | awk -v pat="$pattern" 'BEGIN{IGNORECASE=1} $0 ~ pat {print $1; exit}'
}

dismiss_language_selection_dialog() {
    local win_id
    win_id=$(get_window_id_by_title "Language selection" || true)
    if [ -z "$win_id" ]; then
        return 1
    fi

    # Activate the dialog and confirm the default language (English).
    DISPLAY=:1 xdotool windowactivate --sync "$win_id" 2>/dev/null || true
    sleep 0.5

    # Clicking the OK button by geometry is more reliable than relying on tab order.
    # Use window-relative coordinates so we don't depend on where the dialog appears.
    local geom=""
    geom=$(DISPLAY=:1 xdotool getwindowgeometry --shell "$win_id" 2>/dev/null || true)
    if [ -n "$geom" ]; then
        eval "$geom"
        local click_x=$((WIDTH - 55))
        local click_y=$((HEIGHT - 23))
        DISPLAY=:1 xdotool mousemove --window "$win_id" --sync "$click_x" "$click_y" click 1 2>/dev/null || true
        sleep 0.5
    fi

    # Fallback: Tab -> Cancel -> OK, then Return.
    if DISPLAY=:1 wmctrl -l | grep -qi "Language selection"; then
        DISPLAY=:1 xdotool key --window "$win_id" Tab Tab Return 2>/dev/null || \
            DISPLAY=:1 xdotool key --window "$win_id" Return 2>/dev/null || true
        sleep 0.5
    fi
    sleep 0.5
    return 0
}

get_invesalius_window_id() {
    DISPLAY=:1 wmctrl -l | grep -i "InVesalius" | head -1 | awk '{print $1}'
}

focus_invesalius() {
    local win_id
    win_id=$(get_invesalius_window_id)
    if [ -n "$win_id" ]; then
        DISPLAY=:1 wmctrl -i -a "$win_id"
        sleep 0.5
        return 0
    fi
    return 1
}

dismiss_startup_dialogs() {
    # Send a few generic keys to dismiss any startup dialogs
    if DISPLAY=:1 wmctrl -l | grep -qi "Language selection"; then
        dismiss_language_selection_dialog || true
    fi
    if focus_invesalius; then
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 0.5
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 0.5
    fi
}

ensure_dicom_series_present() {
    local series_dir="$1"
    if [ ! -d "$series_dir" ]; then
        echo "DICOM series directory not found: $series_dir"
        return 1
    fi
    # `find` does not traverse symlinked directories unless given a trailing slash
    # (or -L). Many of our datasets are exposed via symlinks for convenience.
    if ! find -L "$series_dir" -type f \( -iname "*.dcm" -o -iname "*.dicom" -o -iname "*.ima" \) -print -quit | grep -q .; then
        # Some DICOM sets ship without a standard extension; accept "any file" as a fallback if DCMTK isn't present.
        if command -v dcmdump >/dev/null 2>&1; then
            local sample
            sample=$(find -L "$series_dir" -type f -print -quit)
            if [ -z "$sample" ] || ! dcmdump "$sample" >/dev/null 2>&1; then
                echo "No DICOM files found in $series_dir"
                return 1
            fi
        else
            if ! find -L "$series_dir" -type f -print -quit | grep -q .; then
                echo "No DICOM files found in $series_dir"
                return 1
            fi
        fi
    fi
    if ! find -L "$series_dir" -type f -print -quit | grep -q .; then
        echo "No files found in $series_dir"
        return 1
    fi
    return 0
}

pick_dicom_import_dir() {
    # Return a directory path appropriate for `invesalius-launch -i <dir>`.
    # Prefer the directory containing a DICOM file (many importers are non-recursive).
    local series_dir="$1"
    local sample=""

    sample=$(find -L "$series_dir" -type f \( -iname "*.dcm" -o -iname "*.dicom" -o -iname "*.ima" \) -print -quit 2>/dev/null || true)
    if [ -n "$sample" ]; then
        dirname "$sample"
        return 0
    fi

    if command -v dcmdump >/dev/null 2>&1; then
        # Scan a handful of files to find a DICOM object, then import that folder.
        while IFS= read -r candidate; do
            if dcmdump "$candidate" >/dev/null 2>&1; then
                dirname "$candidate"
                return 0
            fi
        done < <(find -L "$series_dir" -type f 2>/dev/null | head -n 50)
    fi

    echo "$series_dir"
    return 0
}
