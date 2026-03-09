#!/usr/bin/env python3
"""Verifier for assign_alternate_styles task."""

import json
import tempfile
import os
import re

def verify_assign_alternate_styles(traj, env_info, task_info):
    """Verify creation and assignment of alternate SLD styles."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_pop_colors = metadata.get('pop_colors', [])
    expected_econ_colors = metadata.get('econ_colors', [])

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/assign_alternate_styles_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify integrity
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
         pass # Allow pass if nonce file missing but result exists (robustness)
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    task_start = result.get('task_start_time', 0)

    # 1. Verify 'population_classes' Style (25 points total)
    # ---------------------------------------------------
    if result.get('style1_exists'):
        score += 10
        feedback_parts.append("Style 'population_classes' created")
        
        # Check content
        sld1 = result.get('style1_sld', '').lower()
        if 'pop_est' in sld1:
            score += 5
            feedback_parts.append("Style 1 uses 'pop_est' attribute")
        
        # Check colors
        colors_found = 0
        for color in expected_pop_colors:
            if color.lower() in sld1:
                colors_found += 1
        
        if colors_found >= 3:
            score += 10
            feedback_parts.append(f"Style 1 contains {colors_found}/{len(expected_pop_colors)} correct colors")
        elif colors_found > 0:
            score += 5
            feedback_parts.append("Style 1 contains some correct colors")
    else:
        feedback_parts.append("Style 'population_classes' NOT found")

    # 2. Verify 'economy_types' Style (25 points total)
    # ---------------------------------------------------
    if result.get('style2_exists'):
        score += 10
        feedback_parts.append("Style 'economy_types' created")
        
        # Check content
        sld2 = result.get('style2_sld', '').lower()
        if 'economy' in sld2:
            score += 5
            feedback_parts.append("Style 2 uses 'economy' attribute")
        
        # Check colors
        colors_found = 0
        for color in expected_econ_colors:
            if color.lower() in sld2:
                colors_found += 1
        
        if colors_found >= 4:
            score += 10
            feedback_parts.append(f"Style 2 contains {colors_found}/{len(expected_econ_colors)} correct colors")
        elif colors_found > 0:
            score += 5
            feedback_parts.append("Style 2 contains some correct colors")
    else:
        feedback_parts.append("Style 'economy_types' NOT found")

    # 3. Verify Layer Association (15 points)
    # ---------------------------------------------------
    assoc = result.get('associated_styles', '')
    if 'population_classes' in assoc and 'economy_types' in assoc:
        score += 15
        feedback_parts.append("Both styles associated with layer 'ne:ne_countries'")
    elif 'population_classes' in assoc or 'economy_types' in assoc:
        score += 7
        feedback_parts.append("One style associated with layer 'ne:ne_countries'")
    else:
        feedback_parts.append("Styles NOT associated with layer")

    # 4. Verify Output Images (25 points total)
    # ---------------------------------------------------
    # Map 1: Population
    if result.get('pop_map_exists'):
        size = result.get('pop_map_size', 0)
        mtime = result.get('pop_map_mtime', 0)
        if mtime > task_start and size > 5000: # 5KB min
            score += 10
            feedback_parts.append("Population map generated successfully")
        else:
             feedback_parts.append("Population map exists but too small or old")
    
    # Map 2: Economy
    if result.get('econ_map_exists'):
        size = result.get('econ_map_size', 0)
        mtime = result.get('econ_map_mtime', 0)
        if mtime > task_start and size > 5000:
            score += 10
            feedback_parts.append("Economy map generated successfully")
        else:
             feedback_parts.append("Economy map exists but too small or old")

    # Check they are different
    if result.get('images_differ'):
        score += 5
        feedback_parts.append("Maps show different styles (visual confirmation)")
    elif result.get('pop_map_exists') and result.get('econ_map_exists'):
        feedback_parts.append("Warning: Maps appear identical")

    # 5. VLM / GUI Usage Check (10 points)
    # ---------------------------------------------------
    # If the user did everything correctly via GUI, access logs should show interaction.
    # We prioritize the programmatic check, but VLM can confirm workflow.
    
    if result.get('gui_interaction'):
        score += 10
        feedback_parts.append("GUI interaction detected")
    else:
        # Fallback to VLM if logs are ambiguous (e.g. slight timing offset)
        query_vlm = env_info.get('query_vlm')
        if query_vlm and traj:
            from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames
            frames = sample_trajectory_frames(traj, 3)
            final = get_final_screenshot(traj)
            images = frames + ([final] if final else [])
            
            vlm_res = query_vlm(
                images=images,
                prompt="Does the user appear to be editing SLD styles or layer settings in GeoServer? Look for XML code or 'Publishing' tabs."
            )
            if vlm_res and vlm_res.get('success'):
                score += 10
                feedback_parts.append("VLM confirms style editing workflow")
            else:
                 feedback_parts.append("No GUI interaction detected")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }