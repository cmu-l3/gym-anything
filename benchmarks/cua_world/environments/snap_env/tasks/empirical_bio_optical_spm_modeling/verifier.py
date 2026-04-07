#!/usr/bin/env python3
"""Verifier for empirical_bio_optical_spm_modeling task.

Scoring breakdown (100 total):
  1. Product saved in DIMAP format (10 pts)
  2. NDTI band derived with correct formula (15 pts)
  3. SPM physical model applied with exp() and correct coefficients (25 pts) - MUST PASS FOR OVERALL PASS
  4. Exceedance mask derived with threshold 75.0 (20 pts)
  5. SPM GeoTIFF exported (15 pts)
  6. Mask GeoTIFF exported (15 pts)
  
Pass threshold: 70 points AND SPM model successfully applied.
"""

import json
import os
import tempfile

def verify_spm_modeling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/spm_modeling_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []
    
    # 1. Product Saved (10 pts)
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 10
        feedback.append("Product saved in DIMAP (+10)")
    elif result.get('dim_found'):
        score += 5
        feedback.append("Product found but timestamp unclear (+5)")
    else:
        feedback.append("No saved product found (0/10)")

    # 2. NDTI Derived (15 pts)
    ndti_expr = result.get('ndti_expression', '').lower().replace(' ', '')
    if result.get('has_ndti') and ndti_expr:
        has_div = '/' in ndti_expr
        has_add = '+' in ndti_expr
        has_sub = '-' in ndti_expr
        has_bands = ('band_3' in ndti_expr and 'band_4' in ndti_expr) or ('band3' in ndti_expr and 'band4' in ndti_expr)
        
        if has_div and has_add and has_sub and has_bands:
            score += 15
            feedback.append("NDTI derived with correct expression (+15)")
        elif has_div and has_bands:
            score += 10
            feedback.append("NDTI derived but expression missing some operators (+10)")
        else:
            score += 5
            feedback.append("NDTI band exists but expression unclear (+5)")
    elif result.get('has_ndti'):
        score += 5
        feedback.append("NDTI band exists but no expression found (+5)")
    else:
        # Fallback check unnamed bands
        for expr in result.get('virtual_bands', {}).values():
            e = expr.lower().replace(' ', '')
            if '/' in e and '+' in e and '-' in e and ('band_3' in e or 'band3' in e):
                score += 10
                feedback.append("NDTI-like expression found in unnamed band (+10)")
                break
        else:
            feedback.append("No NDTI band found (0/15)")

    # 3. SPM physical model applied (25 pts)
    spm_expr = result.get('spm_expression', '').lower().replace(' ', '')
    spm_model_applied = False
    
    has_exp = 'exp(' in spm_expr
    has_coeff1 = '25.5' in spm_expr
    has_coeff2 = '3.1' in spm_expr
    
    if result.get('has_spm') and spm_expr:
        if has_exp and has_coeff1 and has_coeff2:
            score += 25
            spm_model_applied = True
            feedback.append("SPM physical model applied correctly (+25)")
        elif has_exp:
            score += 15
            spm_model_applied = True
            feedback.append("SPM model applied but coefficients missing/wrong (+15)")
        else:
            score += 5
            feedback.append("SPM band exists but exp() missing (+5)")
    elif result.get('has_spm'):
        score += 5
        feedback.append("SPM band exists but no expression found (+5)")
    else:
        # Fallback check unnamed bands
        for expr in result.get('virtual_bands', {}).values():
            e = expr.lower().replace(' ', '')
            if 'exp(' in e and ('25.5' in e or '3.1' in e):
                score += 20
                spm_model_applied = True
                feedback.append("SPM model found in unnamed band (+20)")
                break
        else:
            feedback.append("No SPM model found (0/25)")

    # 4. Exceedance Mask Derived (20 pts)
    mask_expr = result.get('exceedance_expression', '').lower().replace(' ', '')
    if result.get('has_exceedance') and mask_expr:
        has_75 = '75.0' in mask_expr or '75' in mask_expr
        has_cond = any(x in mask_expr for x in ['if(', 'if', '>', '?'])
        
        if has_75 and has_cond:
            score += 20
            feedback.append("Exceedance mask derived correctly (+20)")
        elif has_cond:
            score += 10
            feedback.append("Exceedance mask derived but wrong threshold (+10)")
        else:
            score += 5
            feedback.append("Exceedance mask exists but logic unclear (+5)")
    elif result.get('has_exceedance'):
        score += 5
        feedback.append("Exceedance mask exists but no expression found (+5)")
    else:
        # Fallback check unnamed bands
        for expr in result.get('virtual_bands', {}).values():
            e = expr.lower().replace(' ', '')
            if '75' in e and ('>' in e or 'if' in e):
                score += 15
                feedback.append("Exceedance mask found in unnamed band (+15)")
                break
        else:
            feedback.append("No exceedance mask found (0/20)")

    # 5. SPM GeoTIFF Exported (15 pts)
    if result.get('spm_tif_found') and result.get('spm_tif_created_after_start'):
        if result.get('spm_tif_size', 0) > 1024:
            score += 15
            feedback.append("SPM GeoTIFF exported (+15)")
        else:
            score += 5
            feedback.append("SPM GeoTIFF exported but file too small (+5)")
    else:
        feedback.append("SPM GeoTIFF not exported (0/15)")

    # 6. Mask GeoTIFF Exported (15 pts)
    if result.get('mask_tif_found') and result.get('mask_tif_created_after_start'):
        if result.get('mask_tif_size', 0) > 1024:
            score += 15
            feedback.append("Mask GeoTIFF exported (+15)")
        else:
            score += 5
            feedback.append("Mask GeoTIFF exported but file too small (+5)")
    else:
        feedback.append("Mask GeoTIFF not exported (0/15)")

    passed = score >= 70 and spm_model_applied
    if not spm_model_applied:
        feedback.append("FAIL: Core SPM model was not applied correctly")

    return {"passed": passed, "score": score, "feedback": "; ".join(feedback)}