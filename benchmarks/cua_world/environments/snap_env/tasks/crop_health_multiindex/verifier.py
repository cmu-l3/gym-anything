#!/usr/bin/env python3
"""
Verifier for crop_health_multiindex task.

Scoring breakdown (Total: 100 points):
1. DIMAP product saved (15 pts)
2. At least 3 new derived bands (20 pts)
3. Classification band with conditional logic (20 pts)
4. Expressions reference >= 3 of the original bands (15 pts)
5. At least 4 new bands total (10 pts)
6. GeoTIFF exported (10 pts)
7. GeoTIFF non-trivial size (10 pts)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import re


def verify_crop_health_multiindex(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/crop_health_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # 1. DIMAP product saved (15 pts)
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 15
        feedback.append("DIMAP product successfully created (+15)")
    elif result.get('dim_found'):
        score += 10
        feedback.append("DIMAP product found but timestamp unclear (+10)")
    else:
        feedback.append("No saved DIMAP product found (0/15)")

    vbands = result.get('virtual_bands', {})
    total_bands = result.get('total_bands', 0)
    new_bands = total_bands - 4 if total_bands >= 4 else 0

    # 2. At least 3 derived bands (20 pts)
    if len(vbands) >= 3:
        score += 20
        feedback.append(f"Found {len(vbands)} virtual derived bands (+20)")
    elif len(vbands) == 2:
        score += 10
        feedback.append(f"Found only {len(vbands)} virtual derived bands (+10)")
    elif len(vbands) == 1:
        score += 5
        feedback.append("Found only 1 virtual derived band (+5)")
    else:
        # Check if they computed physical bands instead of virtual ones
        if new_bands >= 3:
            score += 15
            feedback.append(f"Found {new_bands} new physical bands (warn: should be virtual) (+15)")
        else:
            feedback.append("Not enough derived bands found (0/20)")

    # 3. Classification band with conditional logic (20 pts)
    conditional_found = False
    for expr in vbands.values():
        el = expr.lower().replace(' ', '')
        if any(op in el for op in ['?', 'if', '>', '<', '==']):
            conditional_found = True
            break
            
    if conditional_found:
        score += 20
        feedback.append("Conditional logic found in band expressions (+20)")
    else:
        feedback.append("No conditional logic found in band expressions (0/20)")

    # 4. Expressions reference >= 3 of 4 original bands (15 pts)
    band_refs = set()
    all_bands = [b.lower() for b in result.get('band_names', [])]
    virtual_band_names = [b.lower() for b in vbands.keys()]
    original_bands = [b for b in all_bands if b not in virtual_band_names]

    for expr in vbands.values():
        el = expr.lower()
        # Regex to find standard references like band_1, band1, $1
        matches = re.findall(r'band_([0-9]+)|band([0-9]+)|\$([0-9]+)', el)
        for m in matches:
            for g in m:
                if g: band_refs.add(g)
        
        # Check against explicitly renamed original bands
        for ob in original_bands:
            if ob in el:
                band_refs.add(ob)

    if len(band_refs) >= 3:
        score += 15
        feedback.append(f"Expressions reference {len(band_refs)} distinct original bands (+15)")
    elif len(band_refs) == 2:
        score += 8
        feedback.append(f"Expressions reference only 2 distinct original bands (+8)")
    elif len(band_refs) == 1:
        score += 3
        feedback.append("Expressions reference only 1 original band (+3)")
    else:
        feedback.append("Expressions do not reference original source bands (0/15)")

    # 5. At least 4 new bands total (10 pts)
    if len(vbands) >= 4 or new_bands >= 4:
        score += 10
        feedback.append(f"At least 4 new bands total found (+10)")
    else:
        feedback.append(f"Less than 4 new bands total found (0/10)")

    # 6. GeoTIFF exported (10 pts)
    if result.get('tif_found') and result.get('tif_created_after_start'):
        score += 10
        feedback.append("GeoTIFF successfully exported (+10)")
    elif result.get('tif_found'):
        score += 5
        feedback.append("GeoTIFF found but timestamp unclear (+5)")
    else:
        feedback.append("No GeoTIFF export found (0/10)")

    # 7. GeoTIFF non-trivial size (10 pts)
    tif_size = result.get('tif_size', 0)
    if tif_size > 50000:
        score += 10
        feedback.append(f"GeoTIFF has valid size ({tif_size} bytes) (+10)")
    elif tif_size > 0:
        score += 5
        feedback.append(f"GeoTIFF is suspiciously small ({tif_size} bytes) (+5)")
    else:
        feedback.append("GeoTIFF is empty or missing (0/10)")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}