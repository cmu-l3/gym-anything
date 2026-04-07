#!/bin/bash
echo "=== Exporting Isolate Transients Results ==="

source /workspace/scripts/task_utils.sh

# Capture visual evidence
take_screenshot /tmp/task_final.png

# Evaluate the generated outputs programmatically using Python
python3 << 'PYEOF'
import os, json, re
import numpy as np
from astropy.io import fits

OUTPUT_DIR = "/home/ga/AstroImages/transient_search/output"

def eval_fits(agent_path, gt_path):
    if not os.path.exists(agent_path):
        return {"exists": False}
    try:
        agent_data = fits.getdata(agent_path).astype(np.float32)
        gt_data = fits.getdata(gt_path).astype(np.float32)
        
        # Handle cases where agent accidentally saved the whole 3D stack
        if agent_data.ndim > 2:
            agent_data = agent_data[0]
            
        if agent_data.shape != gt_data.shape:
            return {"exists": True, "shape_match": False, "agent_shape": str(agent_data.shape)}
            
        # Compute Pearson correlation (handles minor scaling/float differences)
        std_a = np.std(agent_data)
        std_g = np.std(gt_data)
        if std_a == 0 or std_g == 0:
            corr = 0.0
        else:
            corr = float(np.corrcoef(agent_data.flatten(), gt_data.flatten())[0,1])
            
        rmse = float(np.sqrt(np.mean((agent_data - gt_data)**2)))
        max_val = float(np.max(agent_data))
        
        return {
            "exists": True,
            "shape_match": True,
            "correlation": corr,
            "rmse": rmse,
            "max_val": max_val
        }
    except Exception as e:
        return {"exists": True, "error": str(e)}

results = {
    "median": eval_fits(f"{OUTPUT_DIR}/median_stack.fits", "/tmp/gt_median.fits"),
    "max": eval_fits(f"{OUTPUT_DIR}/max_stack.fits", "/tmp/gt_max.fits"),
    "diff": eval_fits(f"{OUTPUT_DIR}/transients_only.fits", "/tmp/gt_diff.fits"),
    "stats_file_exists": False,
    "reported_max": None,
    "gt_max_transient": None
}

# Check for the reported maximum value in the text file
stats_file = f"{OUTPUT_DIR}/transient_stats.txt"
if os.path.exists(stats_file):
    results["stats_file_exists"] = True
    try:
        with open(stats_file, 'r') as f:
            content = f.read()
        
        # Find all integer/float numbers in the document
        numbers = re.findall(r'[-+]?\d*\.\d+|\d+', content)
        if numbers:
            # Take the last number as the intended value
            results["reported_max"] = float(numbers[-1])
    except:
        pass

# Pull in the mathematical ground truth
try:
    with open('/tmp/transient_ground_truth.json', 'r') as f:
        gt = json.load(f)
        results["gt_max_transient"] = gt.get("max_transient_value")
except:
    pass

with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)

print("Evaluation results:")
print(json.dumps(results, indent=2))
PYEOF

# Ensure the framework can read the exported JSON
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="