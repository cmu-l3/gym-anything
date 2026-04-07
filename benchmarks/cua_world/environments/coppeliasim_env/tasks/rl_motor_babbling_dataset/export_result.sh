#!/bin/bash
echo "=== Exporting rl_motor_babbling_dataset Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/rl_motor_babbling_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/rl_dataset.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/dataset_metadata.json"
IMG_DIR="/home/ga/Documents/CoppeliaSim/exports/images"

# Take final screenshot
take_screenshot /tmp/rl_motor_babbling_end_screenshot.png

# Perform Python-based analysis of the exported data
PYTHON_ANALYSIS=$(python3 << 'PYEOF'
import os, csv, json, math

task_start = int(os.environ.get('TASK_START', 0))
csv_path = '/home/ga/Documents/CoppeliaSim/exports/rl_dataset.csv'
json_path = '/home/ga/Documents/CoppeliaSim/exports/dataset_metadata.json'
img_dir = '/home/ga/Documents/CoppeliaSim/exports/images'

result = {
    "csv_exists": False,
    "csv_is_new": False,
    "csv_row_count": 0,
    "has_required_cols": False,
    "pose_variance_m": 0.0,
    "json_exists": False,
    "json_is_new": False,
    "json_valid": False,
    "images_exist": False,
    "image_count": 0,
    "images_match_csv": False,
    "images_are_unique": False
}

# 1. Analyze CSV
if os.path.exists(csv_path):
    result["csv_exists"] = True
    if os.path.getmtime(csv_path) > task_start:
        result["csv_is_new"] = True
    
    try:
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
        
        result["csv_row_count"] = len(rows)
        
        if len(rows) > 0:
            headers = [h.strip().lower() for h in rows[0].keys()]
            
            # Check required cols
            col_checks = {
                'step': any('step' in h for h in headers),
                'j0': any('j0' in h or 'joint0' in h for h in headers),
                'x': any('x' in h or 'ee_x' in h for h in headers),
                'img': any('image' in h or 'file' in h for h in headers)
            }
            result["has_required_cols"] = all(col_checks.values())
            
            # Compute Kinematic Variance (Standard Deviation of end-effector positions)
            x_col = next((h for h in headers if 'x' in h or 'ee_x' in h), None)
            y_col = next((h for h in headers if 'y' in h or 'ee_y' in h), None)
            z_col = next((h for h in headers if 'z' in h or 'ee_z' in h), None)
            
            if x_col and y_col and z_col:
                xs, ys, zs = [], [], []
                for r in rows:
                    try:
                        # Case insensitive lookup
                        r_key_x = next(k for k in r.keys() if k.strip().lower() == x_col)
                        r_key_y = next(k for k in r.keys() if k.strip().lower() == y_col)
                        r_key_z = next(k for k in r.keys() if k.strip().lower() == z_col)
                        xs.append(float(r[r_key_x]))
                        ys.append(float(r[r_key_y]))
                        zs.append(float(r[r_key_z]))
                    except:
                        pass
                
                def std_dev(lst):
                    if len(lst) < 2: return 0.0
                    mean = sum(lst) / len(lst)
                    var = sum((v - mean) ** 2 for v in lst) / len(lst)
                    return math.sqrt(var)
                
                if len(xs) > 1:
                    max_std = max(std_dev(xs), std_dev(ys), std_dev(zs))
                    result["pose_variance_m"] = max_std

            # 2. Analyze Images matching CSV
            img_col = next((h for h in headers if 'image' in h or 'file' in h), None)
            if img_col and os.path.exists(img_dir):
                result["images_exist"] = True
                png_files = [f for f in os.listdir(img_dir) if f.endswith('.png') and os.path.getmtime(os.path.join(img_dir, f)) > task_start]
                result["image_count"] = len(png_files)
                
                # Check if CSV filenames match actual files
                matched = 0
                sizes = set()
                for r in rows:
                    r_key_img = next(k for k in r.keys() if k.strip().lower() == img_col)
                    img_name = r[r_key_img].strip()
                    # Just filename or full path doesn't matter, check if it's in the dir
                    basename = os.path.basename(img_name)
                    full_path = os.path.join(img_dir, basename)
                    if os.path.exists(full_path):
                        matched += 1
                        sizes.add(os.path.getsize(full_path))
                
                if matched >= 50 and result["image_count"] >= 50:
                    result["images_match_csv"] = True
                
                # Check image variance (if all file sizes are exactly the same, they might be duplicated dummy frames)
                if len(sizes) > 3:
                    result["images_are_unique"] = True

    except Exception as e:
        result["error_csv"] = str(e)

# 3. Analyze JSON
if os.path.exists(json_path):
    result["json_exists"] = True
    if os.path.getmtime(json_path) > task_start:
        result["json_is_new"] = True
    
    try:
        with open(json_path, 'r') as f:
            data = json.load(f)
        req = ['total_samples', 'camera_resolution', 'robot_moved']
        if all(k in data for k in req):
            result["json_valid"] = True
    except Exception as e:
        result["error_json"] = str(e)

print(json.dumps(result))
PYEOF
)

cat > /tmp/rl_motor_babbling_result.json << EOF
{
    "task_start": $TASK_START,
    "analysis": $PYTHON_ANALYSIS
}
EOF

echo "Result generated at /tmp/rl_motor_babbling_result.json"
echo "=== Export Complete ==="