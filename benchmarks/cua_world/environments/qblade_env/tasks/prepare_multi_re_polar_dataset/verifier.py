#!/usr/bin/env python3
"""
Verifier for prepare_multi_re_polar_dataset task.

Criteria:
1. Three specific polar files exported (10 pts)
2. Project file saved (10 pts)
3. Files created during task session (anti-gaming)
4. Data content check:
   - Extrapolation: Alpha range covers ~360 degrees (30 pts)
   - Physics: Distinct data for different Re (30 pts)
   - Validity: Not empty, contains numeric data (20 pts)
"""

import json
import os
import zipfile
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_qblade_polar(file_content):
    """
    Parses a QBlade/XFoil polar file.
    Returns a dictionary with 'alpha', 'cl', 'cd' arrays.
    """
    lines = file_content.decode('utf-8', errors='ignore').splitlines()
    data = []
    
    # QBlade export typically has a header. 
    # We look for the start of numeric data.
    # Typical columns: Alpha, Cl, Cd, ...
    
    start_reading = False
    for line in lines:
        parts = line.split()
        if not parts:
            continue
        
        # Check if line is numeric
        try:
            # Try converting first token to float
            float(parts[0])
            # If successful, assume data line
            # Typical polar has at least 3 cols: Alpha, Cl, Cd
            if len(parts) >= 3:
                vals = [float(x) for x in parts]
                data.append(vals)
        except ValueError:
            continue

    if not data:
        return None

    data_arr = np.array(data)
    # Assuming standard XFoil/QBlade export order: Alpha, Cl, Cd...
    # Sometimes it varies, but Alpha is almost always first.
    return {
        'alpha': data_arr[:, 0],
        'cl': data_arr[:, 1],
        'cd': data_arr[:, 2]
    }

def verify_prepare_multi_re_polar_dataset(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence (Base 10 pts)
    files_exist = (result.get('polar_1m_exists') and 
                   result.get('polar_3m_exists') and 
                   result.get('polar_5m_exists'))
    
    if files_exist:
        score += 10
        feedback_parts.append("All 3 polar files exported")
    else:
        feedback_parts.append("Missing one or more polar files")

    # 3. Check Project (10 pts)
    if result.get('project_exists') and result.get('project_size', 0) > 1000:
        score += 10
        feedback_parts.append("Project saved")
    else:
        feedback_parts.append("Project file missing or empty")

    # 4. Content Analysis (80 pts)
    # We need to pull the bundle
    bundle_path = result.get('bundle_path')
    if not bundle_path or not result.get('bundle_exists'):
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts) + " | No data exported for verification"
        }

    temp_bundle = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    try:
        copy_from_env(bundle_path, temp_bundle.name)
        
        with zipfile.ZipFile(temp_bundle.name, 'r') as z:
            filenames = z.namelist()
            
            # Identify specific files by expected names
            f_1m = next((f for f in filenames if "1M" in f or "1000000" in f), None)
            f_3m = next((f for f in filenames if "3M" in f or "3000000" in f), None)
            f_5m = next((f for f in filenames if "5M" in f or "5000000" in f), None)
            
            polar_files = [f_1m, f_3m, f_5m]
            
            if not all(polar_files):
                feedback_parts.append("Could not identify distinct 1M, 3M, 5M files in export")
                # Fallback: just use any 3 files if exact names don't match?
                # The task demanded exact names. We will stick to strict checking or close match.
                # If they used slightly different names, we might fail here. 
                # Let's try to map by file size or order if names fail? 
                # No, strict naming was part of instructions.
            else:
                data_1m = parse_qblade_polar(z.read(f_1m))
                data_3m = parse_qblade_polar(z.read(f_3m))
                data_5m = parse_qblade_polar(z.read(f_5m))
                
                datasets = [data_1m, data_3m, data_5m]
                
                # Check Validity (20 pts)
                if all(d is not None and len(d['alpha']) > 10 for d in datasets):
                    score += 20
                    feedback_parts.append("Files contain valid numeric data")
                    
                    # Check 360 Extrapolation (30 pts)
                    # Extrapolated polars should range roughly -180 to 180
                    ranges = [d['alpha'].max() - d['alpha'].min() for d in datasets]
                    if all(r > 300 for r in ranges):
                        score += 30
                        feedback_parts.append("360 extrapolation confirmed")
                    else:
                        feedback_parts.append("Data does not appear extrapolated to 360 deg")
                        
                    # Check Re Differentiation (Physics) (30 pts)
                    # Higher Re generally means distinct Cl curves
                    # We check if the datasets are identical (copy-paste error)
                    
                    # Simple check: Sum of Cl should differ
                    sums = [np.sum(d['cl']) for d in datasets]
                    if len(set(sums)) == 3:
                        # They are distinct
                        # Optional: Check if Cl_max follows trend (1M < 3M < 5M)
                        # This is physically expected but might be subtle. 
                        # Distinctness is the primary anti-gaming check.
                        score += 30
                        feedback_parts.append("Distinct datasets for different Re")
                    else:
                        feedback_parts.append("Datasets appear identical (duplicated)")
                else:
                    feedback_parts.append("Files missing data or invalid format")

    except Exception as e:
        feedback_parts.append(f"Error verifying content: {e}")
    finally:
        if os.path.exists(temp_bundle.name):
            os.unlink(temp_bundle.name)

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }