#!/bin/bash
echo "=== Exporting synthetic_vision_domain_randomization Result ==="

source /workspace/scripts/task_utils.sh

export TASK_START=$(cat /tmp/synthetic_vision_start_ts 2>/dev/null || echo "0")
take_screenshot /tmp/synthetic_vision_end_screenshot.png

# Run Python script to evaluate the generated dataset comprehensively
python3 << 'PYEOF'
import os, json, csv, glob, hashlib
import numpy as np

task_start = int(os.environ.get("TASK_START", "0"))
out_dir = "/home/ga/Documents/CoppeliaSim/exports/dataset"
csv_file = os.path.join(out_dir, "metadata.csv")
json_file = os.path.join(out_dir, "generation_report.json")

pngs = glob.glob(os.path.join(out_dir, "*.png"))
image_count = len(pngs)

hashes = set()
valid_images = 0
new_images = 0
pixel_variances = []

# Process Image outputs
for p in pngs:
    try:
        mtime = os.stat(p).st_mtime
        if mtime >= task_start:
            new_images += 1
            
        with open(p, 'rb') as f:
            data = f.read()
            hashes.add(hashlib.sha256(data).hexdigest())
            
        try:
            from PIL import Image
            img = Image.open(p)
            img_arr = np.array(img)
            pixel_variances.append(float(np.var(img_arr)))
            valid_images += 1
        except Exception as e:
            pass
    except:
        pass

unique_hashes = len(hashes)
mean_pixel_var = float(np.mean(pixel_variances)) if pixel_variances else 0.0

# Process CSV metadata
csv_exists = os.path.isfile(csv_file)
csv_is_new = False
if csv_exists:
    csv_is_new = os.stat(csv_file).st_mtime >= task_start

csv_rows = 0
csv_vars = {"color": 0.0, "rot": 0.0, "light": 0.0}
csv_has_headers = False

if csv_exists:
    try:
        with open(csv_file, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            csv_rows = len(rows)
            if rows:
                headers = [h.strip().lower() for h in rows[0].keys()]
                
                # Loose but robust check for required domain parameters
                has_fname = any('file' in h for h in headers)
                has_color = any('color' in h or 'r' in h or 'g' in h for h in headers)
                has_rot = any('rot' in h or 'angle' in h or 'euler' in h for h in headers)
                has_light = any('light' in h or 'pos' in h or 'x' in h for h in headers)
                
                csv_has_headers = has_fname and has_color and has_rot and has_light
                
                colors, rots, lights = [], [], []
                for r in rows:
                    try:
                        c = [float(v) for k, v in r.items() if 'color' in k.lower() or k.lower() in ['r','g','b']]
                        rot = [float(v) for k, v in r.items() if 'rot' in k.lower() or 'angle' in k.lower() or 'alpha' in k.lower() or 'beta' in k.lower() or 'gamma' in k.lower()]
                        l = [float(v) for k, v in r.items() if 'light' in k.lower()]
                        
                        if len(c) >= 3: colors.append(c[:3])
                        if len(rot) >= 3: rots.append(rot[:3])
                        if len(l) >= 3: lights.append(l[:3])
                    except:
                        pass
                
                # Calculate variance among parameters to ensure they randomized them
                if len(colors) > 1: csv_vars["color"] = float(np.mean(np.var(colors, axis=0)))
                if len(rots) > 1: csv_vars["rot"] = float(np.mean(np.var(rots, axis=0)))
                if len(lights) > 1: csv_vars["light"] = float(np.mean(np.var(lights, axis=0)))
    except:
        pass

# Process JSON report
json_exists = os.path.isfile(json_file)
json_is_new = False
json_has_fields = False

if json_exists:
    json_is_new = os.stat(json_file).st_mtime >= task_start
    try:
        with open(json_file, 'r') as f:
            data = json.load(f)
        keys_str = " ".join(data.keys()).lower()
        json_has_fields = 'total' in keys_str and 'res' in keys_str and ('camera' in keys_str or 'pos' in keys_str)
    except:
        pass

result = {
    "image_count": image_count,
    "new_images": new_images,
    "unique_hashes": unique_hashes,
    "valid_images": valid_images,
    "mean_pixel_var": mean_pixel_var,
    "csv_exists": csv_exists,
    "csv_is_new": csv_is_new,
    "csv_rows": csv_rows,
    "csv_has_headers": csv_has_headers,
    "csv_vars": csv_vars,
    "json_exists": json_exists,
    "json_is_new": json_is_new,
    "json_has_fields": json_has_fields
}

with open('/tmp/synthetic_vision_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

echo "=== Export Complete ==="