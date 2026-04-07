#!/usr/bin/env python3
"""
Verifier for marketing_clv_bgnbd task.

Scoring (100 pts):
1. Prediction CSV (40 pts):
   - Exists & New (10)
   - Correct columns (10)
   - Reasonable max prediction value (20) [Detects if model is fitted reasonably well]
2. Model Parameters (20 pts):
   - Extracted parameters match CDNOW ground truth within tolerance.
3. Calibration Plot (20 pts):
   - Exists & New (10)
   - Valid size > 5KB (10)
4. Code Execution (20 pts):
   - Script modified (20)

Ground Truth for CDNOW Summary (standard BTYD dataset):
r ~ 0.243, alpha ~ 4.414, a ~ 0.793, b ~ 2.426
Top customers usually have 20-35 expected transactions/year.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_marketing_clv_bgnbd(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. Prediction CSV Checks
    csv_exists = result.get('csv_exists', False)
    csv_new = result.get('csv_is_new', False)
    csv_cols = result.get('csv_cols', '').lower()
    
    if csv_exists and csv_new:
        score += 10
        feedback.append("CSV created (10/10)")
        
        # Check columns
        required = ['frequency', 'recency', 'expected', 'alive']
        missing = [r for r in required if r not in csv_cols]
        if not missing:
            score += 10
            feedback.append("CSV columns correct (10/10)")
        else:
            feedback.append(f"CSV missing columns: {missing} (0/10)")
            
        # Check prediction values
        # For CDNOW, max expected transactions in 52 weeks is typically between 25 and 35
        # If model failed or is garbage, this is usually 0 or huge
        max_pred = result.get('max_prediction', 0)
        try:
            max_pred = float(max_pred)
            if 15.0 <= max_pred <= 50.0:
                score += 20
                feedback.append(f"Max prediction ({max_pred:.2f}) in valid range [15-50] (20/20)")
            else:
                feedback.append(f"Max prediction ({max_pred:.2f}) suspicious - expected ~30 (0/20)")
        except:
            feedback.append("Could not parse max prediction (0/20)")
    else:
        feedback.append("CSV file missing or not created during task (0/40)")

    # 2. Model Parameters Check
    params_content = result.get('params_content', '')
    # Extract numbers
    numbers = [float(x) for x in re.findall(r"-?\d+\.?\d*", params_content)]
    
    # We expect 4 numbers. Order can vary, so we check if *set* of numbers is close
    # Ground truth: 0.243, 4.414, 0.793, 2.426
    # We'll just check if we can find matches for at least 3 of them with 15% tolerance
    targets = [0.243, 4.414, 0.793, 2.426]
    matched = 0
    if len(numbers) >= 4:
        # Simple greedy matching
        remaining_nums = numbers[:]
        for t in targets:
            found = False
            for i, n in enumerate(remaining_nums):
                if abs(n - t) / t < 0.20: # 20% tolerance
                    found = True
                    remaining_nums.pop(i)
                    break
            if found:
                matched += 1
    
    if matched >= 3:
        score += 20
        feedback.append(f"Model parameters match ground truth ({matched}/4 matches) (20/20)")
    elif matched > 0:
        score += 10
        feedback.append(f"Some model parameters match ({matched}/4) (10/20)")
    else:
        feedback.append(f"Model parameters do not match ground truth (found: {numbers}) (0/20)")

    # 3. Plot Check
    if result.get('plot_exists') and result.get('plot_is_new'):
        if result.get('plot_size_kb', 0) > 5:
            score += 20
            feedback.append("Calibration plot created and valid size (20/20)")
        else:
            score += 5
            feedback.append("Calibration plot exists but very small (5/20)")
    else:
        feedback.append("Calibration plot missing (0/20)")

    # 4. Script Check
    if result.get('script_modified', False):
        score += 20
        feedback.append("Analysis script modified (20/20)")
    else:
        feedback.append("Analysis script not modified (0/20)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }