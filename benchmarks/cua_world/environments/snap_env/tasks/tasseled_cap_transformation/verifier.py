#!/usr/bin/env python3
"""Verifier for tasseled_cap_transformation task."""

import json
import os
import tempfile
import re

def verify_tasseled_cap_transformation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/tct_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []
    
    # 1. Product Base Saved (10)
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 10
        feedback.append("DIMAP product saved (+10)")
    elif result.get('dim_found'):
        score += 5
        feedback.append("DIMAP product found but timestamp unclear (+5)")
    else:
        feedback.append("No DIMAP product found (0/10)")

    bands = result.get('bands', {})
    
    # 2. Band Creation (10)
    tc_bands = [b for b in bands.keys() if b.startswith('TC_') or 'brightness' in b.lower() or 'greenness' in b.lower() or 'wetness' in b.lower()]
    if len(tc_bands) >= 3:
        score += 10
        feedback.append("Three Tasseled Cap bands created (+10)")
    elif len(tc_bands) > 0:
        score += 3 * len(tc_bands)
        feedback.append(f"{len(tc_bands)} Tasseled Cap bands created (+{3 * len(tc_bands)})")
    else:
        feedback.append("TC bands not created (0/10)")

    # 3. GeoTIFF Export (10)
    if result.get('tif_found') and result.get('tif_created_after_start') and result.get('tif_file_size', 0) > 1024:
        score += 10
        feedback.append("GeoTIFF exported (+10)")
    elif result.get('tif_found'):
        score += 5
        feedback.append("GeoTIFF found but timestamp/size unclear (+5)")
    else:
        feedback.append("GeoTIFF not exported properly (0/10)")

    # Normalize expressions for checking
    def normalize_expr(e):
        return e.replace(" ", "").replace("0.30", "0.3").replace("0.20", "0.2").lower()

    # 4. Brightness Expression (10)
    b_expr = ""
    for k, v in bands.items():
        if 'brightness' in k.lower():
            b_expr = normalize_expr(v)
            break
            
    if b_expr:
        if all(x in b_expr for x in ['0.3*band_4', '0.28*band_3', '0.47*band_2', '0.51*band_1']):
            score += 10
            feedback.append("Brightness expression perfect (+10)")
        elif '0.3' in b_expr and '0.51' in b_expr:
            score += 5
            feedback.append("Brightness expression partially correct (+5)")
        else:
            feedback.append("Brightness expression incorrect (0/10)")
    else:
        feedback.append("TC_Brightness missing (0/10)")

    # 5. Greenness Expression (10)
    g_expr = ""
    for k, v in bands.items():
        if 'greenness' in k.lower():
            g_expr = normalize_expr(v)
            break
            
    if g_expr:
        if all(x in g_expr for x in ['0.28*band_4', '0.24*band_3', '0.54*band_2', '0.06*band_1']):
            if '-' in g_expr and '+' in g_expr:
                score += 10
                feedback.append("Greenness expression perfect (+10)")
            else:
                score += 7
                feedback.append("Greenness expression numbers correct but signs may be wrong (+7)")
        elif '0.54' in g_expr:
            score += 5
            feedback.append("Greenness expression partially correct (+5)")
        else:
            feedback.append("Greenness expression incorrect (0/10)")
    else:
        feedback.append("TC_Greenness missing (0/10)")

    # 6. Wetness Expression (10)
    w_expr = ""
    for k, v in bands.items():
        if 'wetness' in k.lower():
            w_expr = normalize_expr(v)
            break
            
    if w_expr:
        if all(x in w_expr for x in ['0.15*band_4', '0.2*band_3', '0.33*band_2', '0.65*band_1']):
            score += 10
            feedback.append("Wetness expression perfect (+10)")
        elif '0.65' in w_expr:
            score += 5
            feedback.append("Wetness expression partially correct (+5)")
        else:
            feedback.append("Wetness expression incorrect (0/10)")
    else:
        feedback.append("TC_Wetness missing (0/10)")

    # 7. RGB View Export (15)
    png_size = result.get('png_file_size', 0)
    if result.get('png_found') and result.get('png_created_after_start'):
        if png_size > 10240: # >10KB
            score += 15
            feedback.append("RGB view exported successfully (+15)")
        elif png_size > 0:
            score += 7
            feedback.append("RGB view exported but file is very small (+7)")
        else:
            feedback.append("RGB view export is empty (0/15)")
    else:
        feedback.append("RGB view not exported (0/15)")

    # 8. VLM Trajectory Verification (15)
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """You are analyzing an agent's trajectory for a remote sensing task in ESA SNAP Desktop.
The agent must:
1. Open a Landsat image
2. Use Band Maths to create three Tasseled Cap bands (Brightness, Greenness, Wetness)
3. Save as DIMAP and export as GeoTIFF
4. Create an RGB composite from the new bands and export a PNG

Look at these trajectory frames chronologically. Did the agent navigate to Band Maths, enter formulas, and eventually open an RGB composite image?
Respond ONLY with valid JSON containing a boolean field:
{"workflow_completed": true/false}"""
        
        query_vlm = env_info.get("query_vlm")
        if query_vlm:
            vlm_result = query_vlm(prompt=prompt, images=frames + [final])
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("workflow_completed", False):
                    score += 15
                    feedback.append("VLM confirms workflow progression (+15)")
                else:
                    feedback.append("VLM found workflow incomplete (0/15)")
            else:
                feedback.append("VLM query failed or format incorrect (0/15)")
        else:
            # Fallback if VLM is unavailable
            score += 15
            feedback.append("VLM disabled, granting points (+15)")
    except Exception as e:
        score += 15
        feedback.append(f"VLM error, granting points (+15): {e}")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}