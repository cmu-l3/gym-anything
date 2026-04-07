#!/usr/bin/env python3
"""
Verifier for rgb_crop_vigor_consensus task.
Evaluates SNAP Band Maths output using programmatic XML parsing and file checks.

Scoring system (Total 100):
- DIMAP File Exists & Modified: 15 pts
- VARI Band Authored correctly: 20 pts
- NGRDI Band Authored correctly: 20 pts
- Consensus Mask Logic correct: 20 pts
- ENVI Export Exists: 15 pts
- Non-trivial Execution (size check): 10 pts

Pass Threshold: 75
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rgb_crop_vigor_consensus(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/rgb_crop_vigor_result.json', result_path)
        with open(result_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result from container: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # 1. DIMAP Save check (15 pts)
    if result.get('dimap_found') and result.get('dimap_created_after_start'):
        score += 15
        feedback.append("DIMAP product saved correctly (+15)")
    elif result.get('dimap_found'):
        score += 8
        feedback.append("DIMAP product found but timestamp indicates it might be old (+8)")
    else:
        feedback.append("No saved DIMAP product found (0/15)")

    virtual_bands = result.get('virtual_bands', {})
    virtual_bands_lower = {k.lower(): v.lower() for k, v in virtual_bands.items()}

    # Helper function to check mathematical operators
    def has_math_ops(expr, ops):
        return all(op in expr for op in ops)

    # 2. VARI Expression check (20 pts)
    # Expected logic: (band_2 - band_1) / (band_2 + band_1 - band_3)
    vari_expr = None
    for k, v in virtual_bands_lower.items():
        if 'vari' in k:
            vari_expr = v
            break
            
    if vari_expr:
        has_req_bands = ('band_1' in vari_expr or 'band1' in vari_expr) and \
                        ('band_2' in vari_expr or 'band2' in vari_expr) and \
                        ('band_3' in vari_expr or 'band3' in vari_expr)
        has_req_ops = has_math_ops(vari_expr, ['+', '-', '/'])
        
        if has_req_bands and has_req_ops:
            score += 20
            feedback.append("VARI band expression looks structurally correct (+20)")
        elif has_req_bands or has_req_ops:
            score += 10
            feedback.append(f"VARI band exists but expression '{vari_expr}' seems incomplete (+10)")
        else:
            score += 5
            feedback.append("VARI band exists but expression is malformed (+5)")
    else:
        feedback.append("VARI band not found (0/20)")

    # 3. NGRDI Expression check (20 pts)
    # Expected logic: (band_2 - band_1) / (band_2 + band_1)
    ngrdi_expr = None
    for k, v in virtual_bands_lower.items():
        if 'ngrdi' in k:
            ngrdi_expr = v
            break
            
    if ngrdi_expr:
        has_req_bands = ('band_1' in ngrdi_expr or 'band1' in ngrdi_expr) and \
                        ('band_2' in ngrdi_expr or 'band2' in ngrdi_expr)
        has_req_ops = has_math_ops(ngrdi_expr, ['+', '-', '/'])
        
        if has_req_bands and has_req_ops:
            score += 20
            feedback.append("NGRDI band expression looks structurally correct (+20)")
        elif has_req_bands or has_req_ops:
            score += 10
            feedback.append(f"NGRDI band exists but expression '{ngrdi_expr}' seems incomplete (+10)")
        else:
            score += 5
            feedback.append("NGRDI band exists but expression is malformed (+5)")
    else:
        feedback.append("NGRDI band not found (0/20)")

    # 4. Consensus Mask check (20 pts)
    # Expected logic: VARI > 0.15 AND NGRDI > 0.05
    mask_expr = None
    for k, v in virtual_bands_lower.items():
        if 'mask' in k or 'vigor' in k or 'high' in k:
            mask_expr = v
            break
            
    if mask_expr:
        has_logic = 'and' in mask_expr or '&&' in mask_expr or '&' in mask_expr or '?' in mask_expr or 'if' in mask_expr
        has_thresh = '0.15' in mask_expr and '0.05' in mask_expr
        has_greater_than = '>' in mask_expr
        
        if has_logic and has_thresh and has_greater_than:
            score += 20
            feedback.append("Consensus mask logic looks correct (+20)")
        elif has_logic or has_thresh:
            score += 10
            feedback.append(f"Consensus mask exists but logic '{mask_expr}' is missing some constraints (+10)")
        else:
            score += 5
            feedback.append(f"Consensus mask exists but expression '{mask_expr}' is likely incorrect (+5)")
    else:
        # Check if they put the logic directly without naming it mask
        logic_found_elsewhere = False
        for k, v in virtual_bands_lower.items():
            if '0.15' in v and '0.05' in v and ('>' in v) and ('and' in v or '&&' in v):
                score += 15
                feedback.append("Consensus mask logic found in poorly named band (+15)")
                logic_found_elsewhere = True
                break
        
        if not logic_found_elsewhere:
            feedback.append("Consensus mask not found (0/20)")

    # 5. ENVI Export check (15 pts)
    if result.get('envi_hdr_found') and result.get('envi_created_after_start'):
        score += 15
        feedback.append("ENVI export header found (+15)")
    elif result.get('envi_hdr_found'):
        score += 8
        feedback.append("ENVI export found but timestamp may be old (+8)")
    else:
        feedback.append("ENVI export not found (0/15)")

    # 6. Non-trivial Execution (10 pts)
    envi_size = result.get('envi_file_size', 0)
    if envi_size > 1024 * 1024:  # > 1MB
        score += 10
        feedback.append(f"ENVI data size is substantial ({envi_size/1024/1024:.1f} MB) (+10)")
    elif envi_size > 0:
        score += 5
        feedback.append(f"ENVI data size is small ({envi_size} bytes) (+5)")
    else:
        feedback.append("No ENVI data or size is 0 (0/10)")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }