#!/bin/bash
echo "=== Exporting Galaxy Morphological Asymmetry Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE evaluating or closing AIJ
take_screenshot /tmp/task_end_screenshot.png

# Run python evaluation inside the container to safely analyze FITS files
# The script will output to /tmp/task_result.json
python3 << 'PYEOF'
import os
import json
import re
import math
import numpy as np

try:
    from astropy.io import fits
    ASTROPY_AVAILABLE = True
except ImportError:
    ASTROPY_AVAILABLE = False

# Paths
orig_path = "/home/ga/AstroImages/raw/uit_galaxy_sample.fits"
agent_path = "/home/ga/AstroImages/morphology/asymmetry_residual.fits"
stats_path = "/home/ga/AstroImages/morphology/asymmetry_stats.txt"

result = {
    "astropy_available": ASTROPY_AVAILABLE,
    "residual_exists": False,
    "residual_shape_correct": False,
    "correlation_with_gt": 0.0,
    "stats_report_exists": False,
    "reported_mean": None,
    "reported_std": None,
    "reported_min": None,
    "reported_max": None,
    "actual_residual_mean": None,
    "actual_residual_std": None
}

if ASTROPY_AVAILABLE and os.path.exists(agent_path) and os.path.exists(orig_path):
    result["residual_exists"] = True
    
    try:
        # Load FITS data
        orig_data = fits.getdata(orig_path).astype(float)
        agent_data = fits.getdata(agent_path).astype(float)
        
        # Squeeze in case AIJ added phantom dimensions (e.g., z=1)
        orig_data = np.squeeze(orig_data)
        agent_data = np.squeeze(agent_data)
        
        # Calculate theoretical Ground Truth Difference Residual
        # Difference = |I1 - I2| where I2 is I1 rotated 180 deg
        gt_data = np.abs(orig_data - np.rot90(orig_data, 2))
        
        # Check shapes
        if orig_data.shape == agent_data.shape:
            result["residual_shape_correct"] = True
            
            # Compute Pearson Correlation between agent's output and exact ground truth
            agent_flat = agent_data.flatten()
            gt_flat = gt_data.flatten()
            
            std_agent = np.std(agent_flat)
            std_gt = np.std(gt_flat)
            
            if std_agent > 0 and std_gt > 0:
                corr = np.corrcoef(agent_flat, gt_flat)[0, 1]
                result["correlation_with_gt"] = float(corr) if not math.isnan(corr) else 0.0
            else:
                result["correlation_with_gt"] = 0.0
                
        # Record actual statistics of what the agent saved
        result["actual_residual_mean"] = float(np.mean(agent_data))
        result["actual_residual_std"] = float(np.std(agent_data))
        
    except Exception as e:
        result["fits_eval_error"] = str(e)

if os.path.exists(stats_path):
    result["stats_report_exists"] = True
    try:
        with open(stats_path, "r") as f:
            content = f.read().lower()
            
        # Parse basic statistics from the text file
        mean_match = re.search(r'mean\s*[:=]?\s*([+-]?[0-9]*\.?[0-9]+(?:[eE][+-]?[0-9]+)?)', content)
        if mean_match:
            result["reported_mean"] = float(mean_match.group(1))
            
        std_match = re.search(r'(?:std|dev|standard)\s*[:=]?\s*([+-]?[0-9]*\.?[0-9]+(?:[eE][+-]?[0-9]+)?)', content)
        if std_match:
            result["reported_std"] = float(std_match.group(1))
            
        min_match = re.search(r'min(?:imum)?\s*[:=]?\s*([+-]?[0-9]*\.?[0-9]+(?:[eE][+-]?[0-9]+)?)', content)
        if min_match:
            result["reported_min"] = float(min_match.group(1))
            
        max_match = re.search(r'max(?:imum)?\s*[:=]?\s*([+-]?[0-9]*\.?[0-9]+(?:[eE][+-]?[0-9]+)?)', content)
        if max_match:
            result["reported_max"] = float(max_match.group(1))
            
    except Exception as e:
        result["stats_parse_error"] = str(e)

# Save the comprehensive result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Ensure permissions so host can pull it
chmod 666 /tmp/task_result.json 2>/dev/null || true

# Close AstroImageJ
close_astroimagej

echo "=== Export Complete ==="