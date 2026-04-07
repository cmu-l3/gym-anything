#!/bin/bash
echo "=== Exporting insert_event_markers result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Find the newest recording file created after task start
# We look for files in RECORDINGS_DIR that are NOT in /tmp/existing_recordings.txt
NEW_FILE=""
NEW_FILE_MTIME=0

# List current files
ls -1 "$RECORDINGS_DIR" > /tmp/current_recordings.txt

# Find differences (new files)
comm -13 <(sort /tmp/existing_recordings.txt) <(sort /tmp/current_recordings.txt) > /tmp/new_files.txt

# Identify the valid recording file (largest/newest if multiple)
while read -r filename; do
    filepath="$RECORDINGS_DIR/$filename"
    if [ -f "$filepath" ]; then
        # Check modification time
        mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo 0)
        if [ "$mtime" -ge "$TASK_START" ]; then
            # Valid candidate
            if [ -z "$NEW_FILE" ] || [ "$mtime" -gt "$NEW_FILE_MTIME" ]; then
                NEW_FILE="$filepath"
                NEW_FILE_MTIME="$mtime"
            fi
        fi
    fi
done < /tmp/new_files.txt

echo "New recording file identified: $NEW_FILE"

# Analyze the recording file using Python
# We extract: file size, marker counts, and timestamps of markers
python3 -c "
import sys
import os
import csv
import json

file_path = '$NEW_FILE'
result = {
    'file_exists': False,
    'file_size_bytes': 0,
    'marker_counts': {},
    'markers_found': [],
    'marker_separation_ok': False,
    'error': ''
}

if file_path and os.path.exists(file_path):
    result['file_exists'] = True
    result['file_size_bytes'] = os.path.getsize(file_path)
    
    try:
        # OpenBCI text files often have comments (%) at top
        # The header line usually starts with '%' or is the first non-comment line
        # We need to find the 'Marker' column if it exists, or infer it.
        # Standard OpenBCI GUI output often puts Marker in the last column.
        
        with open(file_path, 'r', errors='ignore') as f:
            lines = f.readlines()
            
        # Parse data
        markers = []
        last_marker_sample = -1000
        
        # Simple heuristic parser
        # 1. Find header row
        header_index = -1
        col_map = {}
        
        for i, line in enumerate(lines):
            if 'Sample Index' in line or 'Timestamp' in line:
                header_index = i
                # Parse header to find marker column
                # Remove leading % if present
                clean_line = line.strip().lstrip('%').strip()
                headers = [h.strip() for h in clean_line.split(',')]
                for idx, h in enumerate(headers):
                    col_map[h] = idx
                break
        
        marker_col_idx = -1
        # Try to find explicit Marker column
        for key in col_map:
            if 'Marker' in key:
                marker_col_idx = col_map[key]
                break
        
        # If no explicit marker column, usually it's one of the last columns in GUI v5
        # but let's be strict: if we can't find it, we search row by row for values 1, 2, 3
        # in the last column (common location)
        
        data_start = header_index + 1 if header_index >= 0 else 0
        
        valid_markers = {1, 2, 3}
        found_marker_values = set()
        
        for i in range(data_start, len(lines)):
            line = lines[i].strip()
            if not line or line.startswith('%'): continue
            
            parts = [p.strip() for p in line.split(',')]
            
            # Try to extract marker value
            val = 0
            if marker_col_idx >= 0 and marker_col_idx < len(parts):
                try:
                    val = float(parts[marker_col_idx])
                except:
                    pass
            else:
                # Fallback: check last column if it looks like an integer marker
                # Markers are usually 0, 1, 2, 3...
                try:
                    # Check last column
                    check_val = float(parts[-1])
                    if check_val in valid_markers:
                        val = check_val
                    # Sometimes formatted timestamp is last, check second to last
                    elif len(parts) > 1:
                        check_val_2 = float(parts[-2])
                        if check_val_2 in valid_markers:
                            val = check_val_2
                except:
                    pass
            
            val = int(val)
            if val in valid_markers:
                # Store tuple: (sample_index_approx, value)
                # We use line number as proxy for sample index if explicit index missing
                markers.append({'line': i, 'value': val})
                found_marker_values.add(val)
        
        result['markers_found'] = markers
        result['unique_markers'] = list(found_marker_values)
        
        # Check separation
        # We want to see if markers 1, 2, 3 appear at distinct times
        # Group by value
        import collections
        locs = collections.defaultdict(list)
        for m in markers:
            locs[m['value']].append(m['line'])
            
        # Simple check: do we have 1, 2, 3?
        has_123 = {1, 2, 3}.issubset(found_marker_values)
        
        # Check temporal spread
        # If all markers appeared within 10 lines, that's suspicious (gaming via file edit?)
        if markers:
            first_line = markers[0]['line']
            last_line = markers[-1]['line']
            # At 250Hz, 2 seconds is 500 samples/lines.
            # We expect at least some spread.
            if (last_line - first_line) > 100:
                result['marker_separation_ok'] = True
            
            # If we only have 1 marker instance, separation check is N/A but strictly False for "sequence"
            if len(markers) < 2:
                result['marker_separation_ok'] = False
                
    except Exception as e:
        result['error'] = str(e)

print(json.dumps(result))
" > /tmp/analysis_result.json

# Combine results
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "new_file_path": "$NEW_FILE",
    "analysis": $(cat /tmp/analysis_result.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="