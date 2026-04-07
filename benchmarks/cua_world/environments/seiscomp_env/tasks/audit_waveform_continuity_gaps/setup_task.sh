#!/bin/bash
echo "=== Setting up task: audit_waveform_continuity_gaps ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

export SEISCOMP_ROOT=/home/ga/seiscomp
SDS_ROOT="$SEISCOMP_ROOT/var/lib/archive"
YEAR=2024
DOY=001

# Wait for desktop environment
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

if [ ! -d "$SDS_ROOT" ]; then
    echo "ERROR: SDS archive not found! Make sure SeisComP base data is loaded."
    exit 1
fi

echo "--- Injecting gaps into waveform data ---"

# Function to inject gap deterministically using SeisComP's scart tool
inject_gap() {
    local net=$1
    local sta=$2
    local cha=$3
    local start_time_iso=$4  # "2024-01-01 07:10:30"
    local end_time_iso=$5    # "2024-01-01 07:10:40"
    local gap_len=$6
    
    local file_path=$(find "$SDS_ROOT/$YEAR/$net/$sta" -name "${net}.${sta}..${cha}.D.${YEAR}.${DOY}" 2>/dev/null | head -1)
    
    if [ -z "$file_path" ]; then
        echo "WARN: File for $net.$sta not found, skipping gap injection."
        return
    fi
    
    echo "Processing $net.$sta.$cha to inject ${gap_len}s gap..."
    local base=$(basename "$file_path")
    local tmp_p1="/tmp/${base}_p1.mseed"
    local tmp_p2="/tmp/${base}_p2.mseed"
    
    # Extract data before the gap
    su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH scart -t '1970-01-01 00:00:00~${start_time_iso}' '$file_path' > '$tmp_p1' 2>/dev/null"
    
    # Extract data after the gap
    su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH scart -t '${end_time_iso}~2030-01-01 00:00:00' '$file_path' > '$tmp_p2' 2>/dev/null"
    
    # Combine (Gap created by missing data in between)
    cat "$tmp_p1" "$tmp_p2" > "$file_path"
    
    # Cleanup
    rm -f "$tmp_p1" "$tmp_p2"
    
    echo "  Gap injected successfully."
}

# Gap 1: GE.TOLI..BHZ - 10 second gap around 07:10:30
# 2024-01-01 07:10:30 to 2024-01-01 07:10:40
inject_gap "GE" "TOLI" "BHZ" "2024-01-01 07:10:30" "2024-01-01 07:10:40" 10

# Gap 2: GE.GSI..BHZ - 45 second gap around 07:12:00
# 2024-01-01 07:12:00 to 2024-01-01 07:12:45
inject_gap "GE" "GSI" "BHZ" "2024-01-01 07:12:00" "2024-01-01 07:12:45" 45

# Ensure correct ownership
chown -R ga:ga "$SDS_ROOT"

# Ensure clean start state
rm -f /home/ga/gap_report.csv
rm -f /tmp/task_result.json

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="