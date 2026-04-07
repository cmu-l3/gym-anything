#!/usr/bin/env python3
"""
Verifier for panel_gasoline_elasticity task.

Verifies:
1. Correct installation and usage of 'plm' (via script check and output generation).
2. Econometric results:
   - Fixed Effects Price Elasticity should be inelastic (approx -0.3).
   - Hausman test should reject null (p < 0.05), preferring Fixed Effects.
3. Visualization creation.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_panel_gasoline_elasticity(traj, env_info, task_info):
    """
    Verify the panel data analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Metadata ranges
    meta = task_info.get('metadata', {})
    expected_elasticity_range = meta.get('expected_price_elasticity_fe_range', [-0.45, -0.15]) # slightly wider tolerance

    # Criterion 1: Model Comparison CSV (30 pts)
    if result.get('csv_exists'):
        score += 10
        feedback.append("Model comparison CSV exists (+10)")
        
        # Check value accuracy
        try:
            fe_elast = float(result.get('fe_price_elasticity'))
            if expected_elasticity_range[0] <= fe_elast <= expected_elasticity_range[1]:
                score += 20
                feedback.append(f"Fixed Effects Price Elasticity ({fe_elast}) is within expected range {expected_elasticity_range} (+20)")
            else:
                feedback.append(f"Fixed Effects Price Elasticity ({fe_elast}) is out of range {expected_elasticity_range} (0)")
        except (ValueError, TypeError):
            feedback.append("Could not parse numeric elasticity from CSV (0)")
    else:
        feedback.append("Model comparison CSV missing (0)")

    # Criterion 2: Hausman Test (20 pts)
    if result.get('txt_exists'):
        score += 10
        feedback.append("Hausman result text file exists (+10)")
        
        # Check if p-value implies Fixed Effects (p < 0.05)
        try:
            pval_str = result.get('hausman_pval')
            if pval_str is not None and pval_str != 'null':
                pval = float(pval_str)
                if pval < 0.05:
                    score += 10
                    feedback.append(f"Hausman p-value ({pval}) correctly identifies Fixed Effects preference (+10)")
                else:
                    feedback.append(f"Hausman p-value ({pval}) is unusually high, expected < 0.05 (0)")
        except (ValueError, TypeError):
            # If text exists but we couldn't parse number, check if they wrote "Fixed Effects" manually?
            # The export script only extracts 0.xxxxx, so if that failed, we assume failure on rigorous check.
            feedback.append("Could not parse p-value from text file (0)")
    else:
        feedback.append("Hausman result text file missing (0)")

    # Criterion 3: Heterogeneity Plot (20 pts)
    if result.get('png_exists'):
        size = result.get('png_size_bytes', 0)
        if size > 20480: # > 20KB
            score += 20
            feedback.append(f"Heterogeneity plot created and valid size ({size} bytes) (+20)")
        elif size > 0:
            score += 10
            feedback.append("Heterogeneity plot created but suspiciously small (<20KB) (+10)")
    else:
        feedback.append("Heterogeneity plot missing (0)")

    # Criterion 4: Script Implementation (30 pts)
    if result.get('script_modified'):
        score += 10
        feedback.append("R script modified (+10)")
        
        if result.get('script_contains_plm'):
            score += 20
            feedback.append("Script uses 'plm' package as required (+20)")
        else:
            feedback.append("Script does not appear to use 'plm' package (0)")
    else:
        feedback.append("R script not modified (0)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }