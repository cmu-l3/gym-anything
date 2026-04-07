#!/usr/bin/env python3
"""
Verifier for import_eml_files task.

VERIFICATION METRICS:
1. Folder 'Client Correspondence' was created (20 pts)
2. Folder contains emails (15 pts)
3. Correct email count (7 imported) (20 pts)
4. Imported subjects match the original files (20 pts)
5. Anti-gaming: Valid headers & timestamps (10 pts)
6. VLM Trajectory Verification: Workflow actually executed (15 pts)

Pass threshold: 60 points + Folder must exist + At least 1 email imported.
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a desktop agent's workflow. The task is to import 7 .eml email files from a local directory (~/Documents/OldEmails) into Thunderbird.

Please analyze these trajectory frames (sampled from start to finish) and the final screenshot. 
Look for evidence of the following workflow stages:
1. FILE_MANAGER_OPEN: Is a file manager (like Nautilus) open showing .eml files?
2. THUNDERBIRD_INTERACTION: Is Thunderbird open and actively being used?
3. DRAG_AND_DROP_OR_IMPORT: Is there visual evidence of emails being selected, dragged, or imported via menus?
4. FOLDER_VISIBLE: Is a 'Client Correspondence' folder visible in the Thunderbird sidebar?

Respond strictly in JSON format:
{
    "file_manager_visible": true/false,
    "thunderbird_active": true/false,
    "import_action_observed": true/false,
    "folder_visible": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what is observed across frames"
}
"""

def verify_import_eml_files(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch JSON result file from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    mbox_data = result.get('mbox_data', {})
    expected_count = task_info.get('metadata', {}).get('expected_eml_count', 7)
    
    # =================================================================
    # Criterion 1: Folder Exists (20 pts)
    # =================================================================
    folder_exists = result.get('folder_exists', False)
    folder_name = result.get('folder_name_found', '')
    
    if folder_exists and folder_name == "Client Correspondence":
        score += 20
        feedback_parts.append("✓ Exact folder 'Client Correspondence' found.")
    elif folder_exists:
        score += 10
        feedback_parts.append(f"~ Folder found with slight name mismatch: '{folder_name}'.")
    else:
        feedback_parts.append("✗ 'Client Correspondence' folder not found.")
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # =================================================================
    # Criterion 2: Folder contains emails (15 pts)
    # =================================================================
    actual_count = mbox_data.get('count', 0)
    if actual_count > 0:
        score += 15
        feedback_parts.append(f"✓ Folder contains {actual_count} emails.")
    else:
        feedback_parts.append("✗ Folder is empty (no emails imported).")
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # =================================================================
    # Criterion 3: Correct Email Count (20 pts)
    # =================================================================
    if actual_count == expected_count:
        score += 20
        feedback_parts.append(f"✓ Exact expected email count ({expected_count}) imported.")
    elif actual_count >= expected_count - 2:
        score += 10
        feedback_parts.append(f"~ Partial import: {actual_count}/{expected_count} emails imported.")
    else:
        score += 5
        feedback_parts.append(f"✗ Too few emails imported: {actual_count}/{expected_count}.")

    # =================================================================
    # Criterion 4: Subject Matches (20 pts)
    # =================================================================
    expected_subjects = [s.lower() for s in result.get('expected_subjects', [])]
    imported_subjects = [s.lower() for s in mbox_data.get('subjects', [])]
    
    matches = sum(1 for subj in imported_subjects if subj in expected_subjects)
    match_ratio = matches / max(len(expected_subjects), 1)
    
    if match_ratio >= 0.9:
        score += 20
        feedback_parts.append(f"✓ Subjects match expected originals ({matches}/{len(expected_subjects)}).")
    elif match_ratio >= 0.5:
        score += 10
        feedback_parts.append(f"~ Partial subject match ({matches}/{len(expected_subjects)}).")
    else:
        feedback_parts.append(f"✗ Imported subjects do not match expectations.")

    # =================================================================
    # Criterion 5: Anti-Gaming Checks (10 pts)
    # =================================================================
    valid_headers = mbox_data.get('valid_headers', 0)
    created_during = result.get('folder_created_during_task', False)
    
    if valid_headers == actual_count and created_during:
        score += 10
        feedback_parts.append("✓ Anti-gaming: Folder created during task & valid email headers present.")
    elif valid_headers > 0:
        score += 5
        feedback_parts.append("~ Anti-gaming: Headers valid, but timestamp check failed/inconclusive.")

    # =================================================================
    # Criterion 6: VLM Trajectory Verification (15 pts)
    # =================================================================
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images_to_analyze = frames + [final_frame] if final_frame else frames
            
            vlm_response = query_vlm(images=images_to_analyze, prompt=VLM_PROMPT)
            
            if vlm_response.get("success"):
                vlm_parsed = vlm_response.get("parsed", {})
                
                vlm_score = 0
                if vlm_parsed.get("file_manager_visible", False): vlm_score += 4
                if vlm_parsed.get("thunderbird_active", False): vlm_score += 4
                if vlm_parsed.get("import_action_observed", False): vlm_score += 4
                if vlm_parsed.get("folder_visible", False): vlm_score += 3
                
                score += vlm_score
                feedback_parts.append(f"✓ VLM Process Verification: scored {vlm_score}/15. Reasoning: {vlm_parsed.get('reasoning', 'None')}")
            else:
                feedback_parts.append("~ VLM check failed to execute, skipping VLM points.")
        except Exception as e:
            logger.warning(f"VLM verification exception: {e}")
            feedback_parts.append("~ VLM verification encountered an error.")
    else:
        # If VLM is not available in test env, award points by default to not penalize
        score += 15
        feedback_parts.append("~ VLM verification not available, automatically awarding trajectory points.")

    # =================================================================
    # Final Result Compilation
    # =================================================================
    passed = score >= 60 and folder_exists and actual_count > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }