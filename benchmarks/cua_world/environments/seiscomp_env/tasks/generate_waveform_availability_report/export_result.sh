#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check for the agent's CSV report
OUTPUT_PATH="/home/ga/reports/waveform_manifest.csv"
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    OUTPUT_SIZE="0"
fi

# 3. Generate the Ground Truth programmatically
# We use scart to read all miniSEED files and parse the output to construct the true metadata.
echo "Generating ground truth from SDS archive..."
cat > /tmp/generate_ground_truth.py << 'EOF'
import os
import glob
import subprocess
import json

archive_dir = "/home/ga/seiscomp/var/lib/archive"
# SDS pattern: YEAR/NET/STA/CHAN.D/NET.STA.LOC.CHAN.D.YEAR.DOY
files = glob.glob(f"{archive_dir}/*/*/*/*/*")

ground_truth = {}

for f in files:
    try:
        # Using scart to inspect the miniSEED file
        # Output format: GE.TOLI..BHZ 2024-01-01 07:05:00.000 ~ 2024-01-01 07:15:00.000, 20 Hz, 12000 samples
        env = os.environ.copy()
        env['SEISCOMP_ROOT'] = '/home/ga/seiscomp'
        env['PATH'] = f"{env['SEISCOMP_ROOT']}/bin:" + env.get('PATH', '')
        env['LD_LIBRARY_PATH'] = f"{env['SEISCOMP_ROOT']}/lib:" + env.get('LD_LIBRARY_PATH', '')

        result = subprocess.run(["scart", "-I", f], capture_output=True, text=True, env=env)
        
        for line in result.stdout.strip().split('\n'):
            parts = line.split()
            if len(parts) >= 6 and '~' in parts:
                stream_id = parts[0]
                
                # Reconstruct Start Time (e.g. 2024-01-01T07:05:00.000)
                start_time = f"{parts[1]}T{parts[2]}"
                
                # Reconstruct End Time
                end_time = f"{parts[4]}T{parts[5].rstrip(',')}"
                
                # Extract sample rate
                sr = 0.0
                for i, p in enumerate(parts):
                    if p.startswith("Hz"):
                        sr = float(parts[i-1])
                        break
                
                # Store the most expansive time range if multiple records found
                if stream_id not in ground_truth:
                    ground_truth[stream_id] = {
                        "start_time": start_time,
                        "end_time": end_time,
                        "sample_rate": sr
                    }
                else:
                    # Update to min start / max end if needed (scart usually aggregates but just in case)
                    if start_time < ground_truth[stream_id]["start_time"]:
                        ground_truth[stream_id]["start_time"] = start_time
                    if end_time > ground_truth[stream_id]["end_time"]:
                        ground_truth[stream_id]["end_time"] = end_time
    except Exception as e:
        print(f"Error processing {f}: {e}")

with open("/tmp/ground_truth.json", "w") as f:
    json.dump(ground_truth, f)
EOF

python3 /tmp/generate_ground_truth.py
rm -f /tmp/generate_ground_truth.py

# 4. Create JSON result summary
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="