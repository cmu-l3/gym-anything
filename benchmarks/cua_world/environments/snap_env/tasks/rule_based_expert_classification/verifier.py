#!/usr/bin/env python3
"""
Verifier for rule_based_expert_classification task.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rule_based_classification(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/task_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # Criterion 1: DIMAP Product Saved (10 pts)
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 10
        feedback.append("DIMAP product successfully saved during task (+10)")
    elif result.get('dim_found'):
        score += 5
        feedback.append("DIMAP product found but timestamp unclear (+5)")
    else:
        feedback.append("DIMAP product not found (0/10)")

    # Analyze bands
    bands = result.get('bands', {})
    
    # Criterion 2: Indices Created (15 pts)
    has_ndwi = any('ndwi' in k for k in bands.keys())
    has_ndvi = any('ndvi' in k for k in bands.keys())
    
    if has_ndwi and has_ndvi:
        score += 15
        feedback.append("Both NDWI and NDVI bands created (+15)")
    elif has_ndwi or has_ndvi:
        score += 7
        feedback.append("Only one index band (NDWI or NDVI) created (+7)")
    else:
        feedback.append("NDWI and NDVI bands missing (0/15)")

    # Criterion 3: Nested Logic Expression for Land Cover (30 pts)
    # Give a bit more weight here since it's the core of the task
    land_cover_band = None
    for k, v in bands.items():
        if 'land_cover' in k or 'landcover' in k or 'class' in k:
            land_cover_band = v
            break
            
    nested_logic_met = False
    if land_cover_band and 'expression' in land_cover_band:
        expr = land_cover_band['expression'].lower()
        # Check for presence of conditional branching
        ifs = expr.count('if') + expr.count('?')
        elses = expr.count('else') + expr.count(':')
        
        if ifs >= 2 and elses >= 2:
            score += 30
            nested_logic_met = True
            feedback.append("Land Cover band contains valid nested conditional logic (+30)")
        elif ifs >= 1 or elses >= 1:
            score += 15
            feedback.append("Land Cover band has conditional logic, but not properly nested (+15)")
        else:
            score += 5
            feedback.append("Land Cover band found but lacks conditional logic (+5)")
    elif land_cover_band:
        feedback.append("Land Cover band found but expression missing (0/30)")
    else:
        feedback.append("Land Cover classification band missing (0/30)")

    # Criterion 4: Custom Metadata Legend (20 pts)
    if land_cover_band and 'description' in land_cover_band:
        desc = land_cover_band['description'].lower()
        # Look for the required legend substrings
        if '1=water' in desc.replace(' ', '') and '4=barren' in desc.replace(' ', ''):
            score += 20
            feedback.append("Legend correctly added to Band Properties description (+20)")
        elif 'water' in desc or 'barren' in desc:
            score += 10
            feedback.append("Band Properties description modified but incomplete legend (+10)")
        else:
            feedback.append("Band Properties description does not match expected legend (0/20)")
    else:
        feedback.append("Band Properties description missing or not edited (0/20)")

    # Criterion 5: GeoTIFF Export (25 pts)
    tif_size = result.get('tif_size', 0)
    if result.get('tif_found') and result.get('tif_created_after_start'):
        if tif_size > 1024:
            score += 25
            feedback.append(f"GeoTIFF correctly exported ({tif_size} bytes) (+25)")
        else:
            score += 10
            feedback.append(f"GeoTIFF exported but suspiciously small ({tif_size} bytes) (+10)")
    elif result.get('tif_found'):
        score += 10
        feedback.append("GeoTIFF found but timestamp indicates it wasn't from this session (+10)")
    else:
        feedback.append("GeoTIFF export not found (0/25)")

    # Total max is 10 + 15 + 30 + 20 + 25 = 100 points
    passed = score >= 75 and nested_logic_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }