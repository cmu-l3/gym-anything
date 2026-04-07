#!/bin/bash
echo "=== Exporting Create Color Index Map Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture bash variables to pass to Python
export TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
export TASK_END=$(date +%s)
export AGENT_FILE="/home/ga/AstroImages/processed/m12_B_minus_V.fits"
export B_FILE="/home/ga/AstroImages/raw/Bcomb.fits"
export V_FILE="/home/ga/AstroImages/raw/Vcomb.fits"

# Check if AstroImageJ was still running
export APP_RUNNING=$(is_aij_running && echo "true" || echo "false")

# Use a Python script to evaluate the FITS file correctness within the container
# This avoids needing to install astropy on the host machine running the verifier
python3 << 'EOF' > /tmp/temp_result.json
import os
import json
import numpy as np

try:
    from astropy.io import fits
    astropy_available = True
except ImportError:
    astropy_available = False

def evaluate():
    task_start = int(os.environ.get('TASK_START', 0))
    task_end = int(os.environ.get('TASK_END', 0))
    agent_file = os.environ.get('AGENT_FILE', '')
    b_file = os.environ.get('B_FILE', '')
    v_file = os.environ.get('V_FILE', '')
    app_running = os.environ.get('APP_RUNNING', 'false') == 'true'
    
    result = {
        "task_start": task_start,
        "task_end": task_end,
        "app_was_running": app_running,
        "file_exists": False,
        "file_created_during_task": False,
        "valid_fits": False,
        "bitpix": 0,
        "mae": float('inf'),
        "shape_match": False,
        "error": None
    }
    
    # 1. Check existence and timestamps
    if os.path.exists(agent_file):
        result["file_exists"] = True
        mtime = os.path.getmtime(agent_file)
        if mtime > task_start:
            result["file_created_during_task"] = True
            
        # 2. Mathematical evaluation (if astropy is available)
        if astropy_available:
            try:
                # Open ground truth files
                with fits.open(b_file) as hdul_b:
                    b_data = hdul_b[0].data.astype(np.float64)
                with fits.open(v_file) as hdul_v:
                    v_data = hdul_v[0].data.astype(np.float64)
                    
                gt_data = b_data - v_data
                
                # Open agent's output file
                with fits.open(agent_file) as hdul_agent:
                    agent_data = hdul_agent[0].data
                    result["bitpix"] = int(hdul_agent[0].header.get('BITPIX', 0))
                    
                    if agent_data is not None:
                        result["valid_fits"] = True
                        
                        # Compare shapes
                        if agent_data.shape == gt_data.shape:
                            result["shape_match"] = True
                            
                            # Calculate Mean Absolute Error (MAE)
                            # ImageJ might use slightly different floating point math than numpy
                            mae = np.mean(np.abs(agent_data.astype(np.float64) - gt_data))
                            result["mae"] = float(mae)
                        else:
                            result["error"] = f"Shape mismatch: expected {gt_data.shape}, got {agent_data.shape}"
                    else:
                        result["error"] = "Agent FITS file contains no data array."
            except Exception as e:
                result["error"] = str(e)
        else:
            result["error"] = "Astropy not available in container."
            
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    evaluate()
EOF

# Safely copy the JSON result to the final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/temp_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="