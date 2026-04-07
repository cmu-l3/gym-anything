#!/bin/bash
echo "=== Exporting retime_animation_breakdown result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/retimed"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python script to analyze the rendered frames
# We calculate a "difference profile" to verify holds vs changes without needing ground truth images.
# A hold means Diff(Frame N, Frame N+1) == 0.
# A change means Diff(Frame N, Frame N+1) > Threshold.

python3 -c "
import os
import json
import sys
import glob
try:
    from PIL import Image, ImageChops, ImageStat
except ImportError:
    print('PIL not found', file=sys.stderr)
    sys.exit(0)

output_dir = '$OUTPUT_DIR'
task_start = $TASK_START

# Gather files
files = sorted(glob.glob(os.path.join(output_dir, '*.png')))
file_stats = []
diff_profile = []

valid_files_count = 0
created_during_task = 0

for i, fpath in enumerate(files):
    # File stats
    st = os.stat(fpath)
    is_new = st.st_mtime > task_start
    if is_new:
        created_during_task += 1
    
    file_stats.append({
        'filename': os.path.basename(fpath),
        'size': st.st_size,
        'new': is_new
    })
    valid_files_count += 1

    # Image diff against next frame
    if i < len(files) - 1:
        try:
            img1 = Image.open(fpath).convert('RGB')
            img2 = Image.open(files[i+1]).convert('RGB')
            
            # Compute difference
            diff = ImageChops.difference(img1, img2)
            stat = ImageStat.Stat(diff)
            # Average pixel difference (0-255)
            avg_diff = sum(stat.mean) / len(stat.mean)
            
            diff_profile.append({
                'frame_idx': i + 1,        # 1-based index of first frame in pair
                'next_frame_idx': i + 2,
                'diff_score': avg_diff
            })
        except Exception as e:
            print(f'Error comparing frames: {e}', file=sys.stderr)

result = {
    'total_files': valid_files_count,
    'files_created_during_task': created_during_task,
    'file_list': file_stats,
    'diff_profile': diff_profile,
    'output_dir_exists': os.path.exists(output_dir)
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f)
"

# 3. Handle permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Result export complete."
cat "$RESULT_JSON" 2>/dev/null