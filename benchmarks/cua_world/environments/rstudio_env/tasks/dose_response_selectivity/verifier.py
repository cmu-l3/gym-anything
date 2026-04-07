#!/usr/bin/env python3
"""
Verifier for dose_response_selectivity task.

Verifies:
1. 'drc' package installation.
2. Ryegrass model comparison (CSV existence, structure, values).
3. S.alba selectivity analysis (CSV existence, correct SI logic).
4. Visualization output (File existence, size).
5. Script content.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dose_response_selectivity(traj, env_info, task_info):
    """
    Verify the dose-response analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Ryegrass Analysis (35 points)
    if result.get('rye_exists') and result.get('rye_is_new'):
        score += 8
        feedback.append("Ryegrass CSV created (8/8)")
        
        if result.get('rye_has_cols'):
            score += 7
            feedback.append("Ryegrass CSV has correct columns (7/7)")
        else:
            feedback.append("Ryegrass CSV missing columns (0/7)")
            
        count = result.get('rye_model_count', 0)
        if count >= 3:
            score += 5
            feedback.append(f"Ryegrass CSV compares {count} models (5/5)")
        else:
            feedback.append(f"Ryegrass CSV has too few models: {count} (0/5)")
            
        if result.get('rye_ed50_valid'):
            score += 15
            feedback.append("Ryegrass ED50 values in valid range (15/15)")
        else:
            feedback.append("Ryegrass ED50 values invalid or missing (0/15)")
    else:
        feedback.append("Ryegrass CSV not found or old (0/35)")

    # 2. Selectivity Analysis (28 points)
    if result.get('alba_exists') and result.get('alba_is_new'):
        score += 8
        feedback.append("Selectivity CSV created (8/8)")
        
        if result.get('alba_has_herbs'):
            score += 5
            feedback.append("Both herbicides present (5/5)")
        else:
            feedback.append("Missing herbicide data (0/5)")
            
        if result.get('alba_si_valid'):
            score += 15
            feedback.append("Selectivity Index Logic Correct (Gly > Ben) (15/15)")
        else:
            feedback.append("Selectivity Index Logic Incorrect (0/15)")
    else:
        feedback.append("Selectivity CSV not found or old (0/28)")

    # 3. Visualization (12 points)
    if result.get('plot_exists') and result.get('plot_is_new'):
        score += 8
        feedback.append("Plot created (8/8)")
        
        size = result.get('plot_size_kb', 0)
        if size >= 30:
            score += 4
            feedback.append("Plot size sufficient (4/4)")
        else:
            feedback.append(f"Plot too small: {size}KB (0/4)")
    else:
        feedback.append("Plot missing (0/12)")

    # 4. Script & Installation (25 points)
    if result.get('script_modified'):
        score += 5
        feedback.append("R script modified (5/5)")
        
        if result.get('script_has_drc'):
            score += 10
            feedback.append("R script uses drc package (10/10)")
        else:
            feedback.append("R script missing drc calls (0/10)")
    else:
        feedback.append("R script not modified (0/15)")

    if result.get('drc_installed'):
        score += 10
        feedback.append("drc package installed successfully (10/10)")
    else:
        feedback.append("drc package NOT installed (0/10)")

    # Final logic
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }