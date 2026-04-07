#!/usr/bin/env python3
"""
Verifier for wildfire_burn_severity_nbr task.

Scoring breakdown (must sum to exactly 100):
  DIMAP Output Exists:                    15 pts
  NBR Band Computed:                      20 pts
  Valid-Pixel Masking (band_2 > 0.05):    20 pts
  Severity Classification logic:          25 pts
  ENVI Export Exists and Valid:           20 pts
                                   TOTAL: 100 pts
Pass threshold: 80
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_wildfire_burn_severity_nbr(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available in environment"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/burn_severity_result.json', result_path)
        with open(result_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or read result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # Criterion 1: DIMAP Output Exists (15 pts)
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 15
        feedback.append("DIMAP product created and saved (+15)")
    elif result.get('dim_found'):
        score += 10
        feedback.append("DIMAP product found but timestamp indicates pre-existing (+10)")
    else:
        feedback.append("DIMAP product not found (0/15)")

    # Criterion 2: NBR Band Computed (20 pts)
    if result.get('nbr_band_found'):
        score += 20
        feedback.append("NBR band found in output (+20)")
    else:
        feedback.append("NBR band not found (0/20)")

    # Criterion 3: Valid-Pixel Masking (20 pts)
    # Target expression: band_2 > 0.05 (allowing for spacing differences)
    valid_expr = result.get('nbr_valid_pixel_expr', '').replace(' ', '')
    if valid_expr:
        if 'band_2>0.05' in valid_expr or 'band2>0.05' in valid_expr or '0.05<band_2' in valid_expr:
            score += 20
            feedback.append("Valid-pixel mask correctly applied to NBR band (+20)")
        elif 'band_2' in valid_expr or '0.05' in valid_expr:
            score += 10
            feedback.append("Partial valid-pixel mask found (+10)")
        else:
            feedback.append("Valid-pixel mask found but incorrect (0/20)")
    else:
        feedback.append("Valid-pixel expression not found (0/20)")

    # Criterion 4: Severity Classification Logic (25 pts)
    class_expr = result.get('burn_severity_expr', '').replace(' ', '')
    if result.get('burn_severity_found') and class_expr:
        # Check for conditional components: checking for either ternary ?, or if/then functions,
        # along with the numbers 0, 1, 2 representing the classes, and the thresholds 0.0 and 0.25
        has_conditional = any(kw in class_expr for kw in ['?', 'if'])
        has_classes = all(c in class_expr for c in ['0', '1', '2'])
        has_thresholds = '0.25' in class_expr
        
        if has_conditional and has_classes and has_thresholds:
            score += 25
            feedback.append("Severity classification with proper conditional logic found (+25)")
        elif has_conditional:
            score += 15
            feedback.append("Severity classification band has conditional logic but may be incomplete (+15)")
        else:
            score += 10
            feedback.append("Severity classification band found but lacks clear conditional logic (+10)")
    elif result.get('burn_severity_found'):
        score += 5
        feedback.append("Severity classification band found but no expression detected (+5)")
    else:
        feedback.append("Severity classification band not found (0/25)")

    # Criterion 5: ENVI Export Exists and Valid (20 pts)
    if result.get('envi_found') and result.get('envi_created_after_start') and result.get('envi_is_valid'):
        score += 20
        feedback.append("ENVI export found and valid (+20)")
    elif result.get('envi_found'):
        score += 10
        feedback.append("ENVI export found but validity or timestamp issues (+10)")
    else:
        feedback.append("ENVI export not found (0/20)")

    # Evaluate pass/fail
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }