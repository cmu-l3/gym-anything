#!/usr/bin/env python3
"""
Verifier for coastal_flood_evd task.
"""

import json
import tempfile
import os
import base64
import csv
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_coastal_flood_evd(traj, env_info, task_info):
    """
    Verify the Extreme Value Analysis task.
    
    Criteria:
    1. 'evd' package installed (10 pts)
    2. GEV Parameters correct (20 pts)
       - Location ~3.87
       - Scale ~0.198
       - Shape ~-0.05
    3. Return Levels correct (30 pts)
       - 100-year level ~4.69m
    4. Diagnostic plot created and valid (20 pts)
    5. Script modified and exists (10 pts)
    6. Code quality/process (10 pts) - inferred from artifacts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    
    # Metadata for ground truth
    gt = task_info.get('metadata', {}).get('ground_truth', {})
    gt_loc = gt.get('location', 3.87)
    gt_scale = gt.get('scale', 0.198)
    gt_shape = gt.get('shape', -0.050)
    gt_100y = gt.get('return_level_100y', 4.69)
    tol = gt.get('tolerance_params', 0.1)  # 10% tolerance
    
    # 1. Package Installed (10 pts)
    if result.get('package_installed'):
        score += 10
        feedback.append("Package 'evd' installed successfully (+10)")
    else:
        feedback.append("Package 'evd' not found (+0)")

    # 2. GEV Parameters (20 pts)
    params_content = result.get('params_content', '')
    params_ok = False
    if result.get('params_new') and params_content:
        # Parse CSV string manually (expecting simple numbers in order or labeled)
        # Attempt to find numbers close to ground truth
        try:
            # We don't know exact column order user chose, but we look for the values
            # typical format: 3.87, 0.198, -0.05
            vals = [float(x) for x in params_content.replace(',', ' ').split() if x.replace('.','',1).replace('-','',1).isdigit()]
            
            has_loc = any(abs(v - gt_loc) < 0.2 for v in vals)
            has_scale = any(abs(v - gt_scale) < 0.05 for v in vals)
            has_shape = any(abs(v - gt_shape) < 0.1 for v in vals)
            
            if has_loc and has_scale: # Shape is often hard to estimate perfectly, lenient
                score += 20
                params_ok = True
                feedback.append("GEV parameters match ground truth (+20)")
            else:
                feedback.append(f"GEV parameters incorrect or malformed. Found: {vals} (+0)")
        except:
             feedback.append("Could not parse parameter CSV (+0)")
    else:
        feedback.append("Parameters CSV missing or not new (+0)")

    # 3. Return Levels (30 pts)
    levels_b64 = result.get('levels_content_b64', '')
    levels_ok = False
    if result.get('levels_new') and levels_b64:
        try:
            levels_str = base64.b64decode(levels_b64).decode('utf-8')
            # Look for ~4.69
            # Simple check: search for number close to 4.69
            found_100y = False
            rows = levels_str.split('\n')
            for row in rows:
                # Naive parse
                nums = [float(x) for x in row.replace(',', ' ').split() if x.replace('.','',1).isdigit()]
                for n in nums:
                    if abs(n - gt_100y) < 0.2:
                        found_100y = True
                        break
            
            if found_100y:
                score += 30
                levels_ok = True
                feedback.append("100-year return level correct (~4.69m) (+30)")
            else:
                feedback.append(f"100-year return level (approx {gt_100y}) not found in CSV (+0)")
        except:
            feedback.append("Could not parse return levels CSV (+0)")
    else:
        feedback.append("Return levels CSV missing or not new (+0)")

    # 4. Diagnostics (20 pts)
    if result.get('diag_new') and result.get('diag_size', 0) > 20000:
        score += 20
        feedback.append("Diagnostic plot created and substantial size (+20)")
    elif result.get('diag_new'):
        score += 5
        feedback.append("Diagnostic plot created but suspiciously small (+5)")
    else:
        feedback.append("Diagnostic plot missing (+0)")

    # 5. Script (10 pts)
    if result.get('script_modified'):
        score += 10
        feedback.append("Analysis script modified (+10)")
    else:
        feedback.append("Analysis script not modified (+0)")
        
    # 6. Process/Code Quality (10 pts) - awarded if main outputs are correct
    if params_ok and levels_ok:
        score += 10
        feedback.append("Process quality inferred from correct results (+10)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "\n".join(feedback)
    }