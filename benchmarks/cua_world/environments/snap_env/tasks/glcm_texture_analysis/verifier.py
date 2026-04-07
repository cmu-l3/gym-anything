#!/usr/bin/env python3
"""
Verifier for GLCM Texture Analysis task.

Scoring breakdown (must sum to exactly 100):
  DIMAP product exists and valid:                15 pts
  GLCM texture bands present (all 4):            25 pts
  `texture_composite` virtual band exists:       20 pts
  Expression references GLCM terms:              15 pts
  GeoTIFF exported:                              15 pts
  GeoTIFF has non-trivial size:                  10 pts
                                          TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_glcm_texture_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/glcm_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # Criterion 1: DIMAP product exists (15 pts)
    # Anti-gaming: Ensure it was created after the task started
    if result.get('dim_found') and result.get('dim_created_after_start'):
        if result.get('dim_data_dir_found'):
            score += 15
            feedback.append("DIMAP product (.dim and .data) saved (+15)")
        else:
            score += 10
            feedback.append("DIMAP .dim saved, but .data directory missing (+10)")
    elif result.get('dim_found'):
        score += 5
        feedback.append("DIMAP product found but timestamp predates task (possible gaming) (+5)")
    else:
        feedback.append("No saved DIMAP product found (0/15)")

    # Criterion 2: GLCM texture bands present (25 pts)
    all_bands = result.get('band_names', [])
    all_bands_lower = [b.lower() for b in all_bands]
    required_glcm = ["contrast", "homogeneity", "entropy", "energy"]
    
    found_glcm = sum(1 for feat in required_glcm if any(feat in b for b in all_bands_lower))
    
    if found_glcm == 4:
        score += 25
        feedback.append("All required GLCM texture bands found (+25)")
    elif found_glcm >= 3:
        score += 18
        feedback.append(f"Most GLCM texture bands found ({found_glcm}/4) (+18)")
    elif found_glcm >= 1:
        score += 10
        feedback.append(f"Some GLCM texture bands found ({found_glcm}/4) (+10)")
    else:
        feedback.append("No GLCM texture bands found (0/25)")

    # Criterion 3: `texture_composite` band exists (20 pts)
    vbands = result.get('virtual_bands', {})
    
    # Exact match for texture_composite
    if "texture_composite" in vbands:
        score += 20
        feedback.append("Virtual band 'texture_composite' exists (+20)")
    elif any("texture_composite" in b for b in all_bands_lower):
        # Found as a regular band, not virtual (maybe saved as physical data)
        score += 15
        feedback.append("Band 'texture_composite' found, but not strictly virtual (+15)")
    elif any("composite" in b for b in all_bands_lower):
        # Named it something similar
        score += 10
        feedback.append("Composite band found with partial name match (+10)")
    else:
        feedback.append("No 'texture_composite' band found (0/20)")

    # Criterion 4: Expression references GLCM terms (15 pts)
    # Find the expression to evaluate
    expr_to_eval = ""
    if "texture_composite" in vbands:
        expr_to_eval = vbands["texture_composite"]
    else:
        # Check if ANY virtual band expression uses the terms
        for e in vbands.values():
            if "contrast" in e.lower() or "entropy" in e.lower():
                expr_to_eval = e
                break

    if expr_to_eval:
        el = expr_to_eval.lower()
        has_contrast = "contrast" in el
        has_entropy = "entropy" in el
        has_homogeneity = "homogeneity" in el
        
        refs = sum([has_contrast, has_entropy, has_homogeneity])
        
        if refs == 3:
            score += 15
            feedback.append("Expression correctly references GLCM components (+15)")
        elif refs == 2:
            score += 10
            feedback.append("Expression partially references GLCM components (+10)")
        elif refs == 1:
            score += 5
            feedback.append("Expression poorly matches expected GLCM components (+5)")
        else:
            feedback.append("Expression does not reference expected GLCM components (0/15)")
    else:
        feedback.append("No suitable band expression found to evaluate (0/15)")

    # Criterion 5: GeoTIFF exported (15 pts)
    if result.get('tif_found') and result.get('tif_created_after_start'):
        score += 15
        feedback.append("GeoTIFF exported successfully (+15)")
    elif result.get('tif_found'):
        score += 5
        feedback.append("GeoTIFF found but timestamp predates task (+5)")
    else:
        feedback.append("GeoTIFF export not found (0/15)")

    # Criterion 6: GeoTIFF non-trivial size (10 pts)
    tif_size = result.get('tif_file_size', 0)
    if tif_size > 50000: # ~50KB
        score += 10
        feedback.append(f"GeoTIFF size is non-trivial ({tif_size//1024} KB) (+10)")
    elif tif_size > 1024:
        score += 5
        feedback.append(f"GeoTIFF size is small ({tif_size//1024} KB) (+5)")
    else:
        feedback.append("GeoTIFF size is trivial or missing (0/10)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }