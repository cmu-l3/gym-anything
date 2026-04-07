#!/usr/bin/env python3
"""
Verifier for configure_demo_presentation task.

A robotics demonstration engineer must configure a Webots scene for a trade show.
Requires configuring WorldInfo title, Viewpoint position/FOV, and Background skyColor.

Scoring (100 points total):
  - File saved at correct path and modified during task: 10 points
  - WorldInfo title strictly matches expected string: 15 points
  - Viewpoint elevated position (Z-component between 2.0 and 5.0): 25 points
  - Viewpoint fieldOfView widened (0.9 to 1.5): 20 points
  - Background skyColor deep blue (B >= 0.1, R <= 0.2, G <= 0.2): 20 points
  - Background skyColor changed from default (not gray/white): 10 points

Pass threshold: 60 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_configure_demo_presentation(traj, env_info, task_info):
    """
    Verify the trade show demo world was correctly configured and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/demo_configured.wbt')
    expected_title = metadata.get('expected_title', 'Robot Navigation Demo - TechExpo 2024')

    score = 0
    feedback_parts = []
    
    # --- Step 1: Check Export JSON for anti-gaming ---
    try:
        result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        result_file.close()
        copy_from_env('/tmp/configure_demo_presentation_result.json', result_file.name)
        with open(result_file.name) as f:
            export_result = json.load(f)
        os.unlink(result_file.name)
    except Exception as e:
        logger.warning(f"Could not load export result JSON: {e}")
        export_result = {}

    file_modified_during_task = export_result.get('file_modified_during_task', False)

    # --- Step 2: Copy the .wbt file independently ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        logger.warning(f"Could not copy .wbt file: {e}")
        try:
            os.unlink(wbt_file.name)
        except Exception:
            pass

    # --- Check file existence ---
    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Save the world with File > Save World As."
        }
        
    if not file_modified_during_task:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file exists, but timestamp indicates it was not saved during this task attempt."
        }

    score += 10
    feedback_parts.append("World file saved at correct path")

    # --- Check WorldInfo Title ---
    world_info_idx = wbt_content.find('WorldInfo')
    if world_info_idx != -1:
        segment = wbt_content[world_info_idx:world_info_idx + 1000]
        title_match = re.search(r'title\s+"([^"]*)"', segment)
        if title_match:
            actual_title = title_match.group(1)
            if actual_title == expected_title:
                score += 15
                feedback_parts.append("WorldInfo title is correct")
            else:
                feedback_parts.append(f"WorldInfo title is '{actual_title}', expected '{expected_title}'")
        else:
            feedback_parts.append("WorldInfo title field not found")
    else:
        feedback_parts.append("WorldInfo node not found")

    # --- Check Viewpoint ---
    vp_idx = wbt_content.find('Viewpoint')
    if vp_idx != -1:
        segment = wbt_content[vp_idx:vp_idx + 1000]
        
        # Check Position Z
        pos_match = re.search(r'position\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', segment)
        if pos_match:
            try:
                z_val = float(pos_match.group(3))
                if 2.0 <= z_val <= 5.0:
                    score += 25
                    feedback_parts.append(f"Viewpoint position elevated correctly (Z={z_val})")
                else:
                    feedback_parts.append(f"Viewpoint Z position is {z_val}, expected ~3.0 (overhead view)")
            except ValueError:
                feedback_parts.append("Failed to parse Viewpoint position values")
        else:
            feedback_parts.append("Viewpoint position field not found")
            
        # Check FOV
        fov_match = re.search(r'fieldOfView\s+([\d.-]+)', segment)
        if fov_match:
            try:
                fov_val = float(fov_match.group(1))
                if 0.9 <= fov_val <= 1.5:
                    score += 20
                    feedback_parts.append(f"Viewpoint fieldOfView correctly widened ({fov_val})")
                else:
                    feedback_parts.append(f"Viewpoint fieldOfView is {fov_val}, expected ~1.2")
            except ValueError:
                feedback_parts.append("Failed to parse Viewpoint fieldOfView")
        else:
            feedback_parts.append("Viewpoint fieldOfView field not found")
    else:
        feedback_parts.append("Viewpoint node not found")

    # --- Check Background skyColor ---
    bg_idx = wbt_content.find('Background')
    if bg_idx != -1:
        segment = wbt_content[bg_idx:bg_idx + 1000]
        color_match = re.search(r'skyColor\s+\[?\s*([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)\s*\]?', segment)
        if color_match:
            try:
                r_val = float(color_match.group(1))
                g_val = float(color_match.group(2))
                b_val = float(color_match.group(3))
                
                # Check if it's no longer the default gray/white
                is_default = (abs(r_val - 0.7) < 0.05 and abs(g_val - 0.7) < 0.05 and abs(b_val - 0.7) < 0.05) or \
                             (abs(r_val - 1.0) < 0.05 and abs(g_val - 1.0) < 0.05 and abs(b_val - 1.0) < 0.05)
                             
                if not is_default:
                    score += 10
                    feedback_parts.append("Background skyColor changed from default")
                    
                    # Check if it's the required dark blue (0.05 0.05 0.2)
                    if b_val >= 0.1 and r_val <= 0.2 and g_val <= 0.2:
                        score += 20
                        feedback_parts.append(f"Background skyColor is correct dark blue ({r_val} {g_val} {b_val})")
                    else:
                        feedback_parts.append(f"Background skyColor is ({r_val} {g_val} {b_val}), expected navy blue (~0.05 0.05 0.2)")
                else:
                    feedback_parts.append("Background skyColor is still default gray/white")
                    
            except ValueError:
                feedback_parts.append("Failed to parse Background skyColor values")
        else:
            feedback_parts.append("Background skyColor field not found")
    else:
        feedback_parts.append("Background node not found")

    # --- Final Assessment ---
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }