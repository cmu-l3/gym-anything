#!/usr/bin/env python3
"""
Verifier for bsi_erosion_risk_mapping task.
Evaluates SNAP XML output for multi-band math expressions and conditionals.

Scoring:
- DIMAP file created successfully: 15 pts
- GeoTIFF exported successfully (>1MB): 15 pts
- BSI band named and created: 10 pts
- BSI formula correctly uses addition/subtraction/division of the 4 bands: 25 pts
- Risk band named and created: 10 pts
- Risk logic checks for > 0.10: 25 pts
TOTAL: 100 points, Pass Threshold: 75 points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bsi_erosion_risk(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve exported results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/bsi_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Check DIMAP creation (15 pts)
    if result.get('dim_found') and result.get('dim_created_during_task'):
        score += 15
        feedback_parts.append("DIMAP product created (+15)")
    elif result.get('dim_found'):
        score += 5
        feedback_parts.append("DIMAP found but timestamp predates task start (+5)")
    else:
        feedback_parts.append("DIMAP product missing (0/15)")

    # 2. Check GeoTIFF export (15 pts)
    if result.get('tif_found') and result.get('tif_created_during_task'):
        if result.get('tif_size_bytes', 0) > 1024 * 1024:  # >1MB expected for 6 bands
            score += 15
            feedback_parts.append("GeoTIFF exported successfully (+15)")
        elif result.get('tif_size_bytes', 0) > 1024:
            score += 10
            feedback_parts.append("GeoTIFF exported but smaller than expected (+10)")
        else:
            feedback_parts.append("GeoTIFF exported but empty (0/15)")
    else:
        feedback_parts.append("GeoTIFF missing (0/15)")

    # 3. Check BSI Band existence (10 pts)
    if result.get('bsi_band_exists'):
        score += 10
        feedback_parts.append("BSI band exists (+10)")
    else:
        feedback_parts.append("BSI band missing (0/10)")

    # 4. Check BSI formula logic (25 pts)
    bsi_expr = result.get('bsi_expression', '').lower().replace(' ', '')
    if bsi_expr:
        # Expected components: band_1, band_2, band_3, band_4, /, -
        has_bands = all(b in bsi_expr for b in ['band_1', 'band_2', 'band_3', 'band_4'])
        has_ops = '/' in bsi_expr and '-' in bsi_expr and '+' in bsi_expr
        
        if has_bands and has_ops:
            score += 25
            feedback_parts.append("BSI math expression structure is correct (+25)")
        elif has_bands:
            score += 15
            feedback_parts.append("BSI math expression references bands but operators missing/wrong (+15)")
        else:
            score += 5
            feedback_parts.append("BSI math expression incomplete (+5)")
    else:
        if result.get('bsi_band_exists'):
            feedback_parts.append("BSI band missing virtual expression (0/25)")

    # 5. Check Risk Mask existence (10 pts)
    if result.get('risk_band_exists'):
        score += 10
        feedback_parts.append("Risk mask band exists (+10)")
    else:
        feedback_parts.append("Risk mask band missing (0/10)")

    # 6. Check Risk Mask logic (25 pts)
    risk_expr = result.get('risk_expression', '').lower().replace(' ', '')
    if risk_expr:
        has_threshold = '0.1' in risk_expr or '.1' in risk_expr
        has_logic = any(op in risk_expr for op in ['if', '?', '>', '>='])
        references_bsi = 'bsi' in risk_expr or ('band_1' in risk_expr and '/' in risk_expr) # Accept inlined BSI

        if references_bsi and has_threshold and has_logic:
            score += 25
            feedback_parts.append("Risk mask conditional logic correct (+25)")
        elif has_threshold and has_logic:
            score += 15
            feedback_parts.append("Risk mask logic correct but explicit BSI reference unclear (+15)")
        elif references_bsi:
            score += 10
            feedback_parts.append("Risk mask references BSI but lacks clear conditional logic (+10)")
        else:
            feedback_parts.append("Risk mask logic incomplete (0/25)")
    else:
        if result.get('risk_band_exists'):
            feedback_parts.append("Risk mask missing virtual expression (0/25)")

    # Ensure key milestones achieved for pass
    passed = score >= 75 and result.get('dim_found') and result.get('bsi_band_exists')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }