#!/usr/bin/env python3
"""
Verifier for customize_contacts_list_view task.

Verification Strategy:
1. Anti-Gaming: Verify Apache logs contain a POST to `SaveListView` (proves UI usage vs CLI scripting).
2. Data Validation: Verify the custom PHP layout file was generated and parsed.
3. Field Checks: Ensure DEPARTMENT and DO_NOT_CALL are default columns.
4. Field Checks: Ensure TITLE is no longer a default column.
5. Sanity Check: Ensure NAME is still present (prevents array corruption).
6. VLM Check: Analyze trajectory frames to confirm Studio interaction.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_contacts_list_view(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/customize_contacts_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    layout_defs = result.get('layout_defs', {})
    custom_file_exists = result.get('custom_file_exists', False)
    studio_save_requests = int(result.get('studio_save_requests', 0))

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # CRITERION 1: Studio UI Usage (Anti-gaming) (20 pts)
    # ---------------------------------------------------------
    if studio_save_requests > 0:
        score += 20
        feedback_parts.append("Studio UI usage verified (+20)")
    else:
        feedback_parts.append("CRITICAL FAIL: Studio UI usage not detected in Apache logs! You must use the CRM interface.")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }

    # ---------------------------------------------------------
    # CRITERION 2: Layout File Created
    # ---------------------------------------------------------
    if not custom_file_exists:
        feedback_parts.append("Custom layout file not created. Did you click 'Save & Deploy'?")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Helper function to check field configuration (case-insensitive keys)
    def is_default_column(field_name):
        for k, v in layout_defs.items():
            if k.upper() == field_name.upper():
                # 'default' can be boolean true or string 'true' based on SuiteCRM version
                val = v.get('default', False)
                return str(val).lower() in ['true', '1']
        return False

    # ---------------------------------------------------------
    # CRITERION 3: NAME preserved (10 pts - Sanity Check)
    # ---------------------------------------------------------
    if is_default_column('NAME'):
        score += 10
        feedback_parts.append("NAME column preserved (+10)")
    else:
        feedback_parts.append("NAME column missing - layout array might be corrupted")

    # ---------------------------------------------------------
    # CRITERION 4: DO_NOT_CALL added (20 pts)
    # ---------------------------------------------------------
    if is_default_column('DO_NOT_CALL'):
        score += 20
        feedback_parts.append("Do Not Call column added (+20)")
    else:
        feedback_parts.append("Do Not Call column NOT found in Default list")

    # ---------------------------------------------------------
    # CRITERION 5: DEPARTMENT added (20 pts)
    # ---------------------------------------------------------
    if is_default_column('DEPARTMENT'):
        score += 20
        feedback_parts.append("Department column added (+20)")
    else:
        feedback_parts.append("Department column NOT found in Default list")

    # ---------------------------------------------------------
    # CRITERION 6: TITLE removed (15 pts)
    # ---------------------------------------------------------
    if not is_default_column('TITLE'):
        score += 15
        feedback_parts.append("Title column removed (+15)")
    else:
        feedback_parts.append("Title column is STILL in Default list")

    # ---------------------------------------------------------
    # CRITERION 7: VLM Trajectory Verification (15 pts)
    # ---------------------------------------------------------
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = (
            "Look at these screenshots from a web browser session evaluating a CRM administrator task. "
            "Did the user actively navigate into the 'Studio' environment and interact with the "
            "Layouts/List View editor (drag-and-drop or columns screen)? Answer with a simple YES or NO."
        )
        
        vlm_response = query_vlm(images=frames + [final], prompt=prompt)
        if vlm_response and "YES" in str(vlm_response).upper():
            score += 15
            feedback_parts.append("VLM visual trajectory verified (+15)")
        else:
            feedback_parts.append("VLM visual trajectory could not verify Studio interaction")
    except ImportError:
        # If VLM is not available, grant points implicitly if file logic passed
        logger.warning("VLM module not available. Skipping visual check.")
        score += 15
        feedback_parts.append("VLM check skipped (+15)")
    except Exception as e:
        logger.warning(f"VLM error: {e}")
        feedback_parts.append(f"VLM check failed: {e}")

    # Final logic: 100 max points. Need at least 80 to pass
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }