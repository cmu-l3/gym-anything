#!/usr/bin/env python3
"""
Verifier for generate_support_logs task.

Verifies:
1. A Support Information ZIP file was created.
2. The file was created during the task window.
3. The 'Database Logs' (PostgreSQL logs) are EXCLUDED from the zip.
4. Visual confirmation of the Support page/process.
"""

import json
import os
import tempfile
import zipfile
import logging
from vlm_utils import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_support_logs(traj, env_info, task_info):
    """
    Verify the support logs task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup score components
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON from Container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Analyze File Existence and Freshness
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    output_path = result.get('output_path', '')

    if output_exists:
        score += 20
        feedback_parts.append("Support file found.")
    else:
        feedback_parts.append("No support file found.")

    if file_created:
        score += 20
        feedback_parts.append("File created during task window.")
    else:
        if output_exists:
            feedback_parts.append("File detected was old (pre-task).")
    
    # 3. Analyze Zip Content (Database Exclusion Check)
    # We need to copy the zip file out to inspect it
    db_excluded = False
    zip_inspect_success = False
    
    if output_exists and output_path:
        temp_zip = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
        try:
            copy_from_env(output_path, temp_zip.name)
            
            if zipfile.is_zipfile(temp_zip.name):
                zip_inspect_success = True
                with zipfile.ZipFile(temp_zip.name, 'r') as zf:
                    file_list = zf.namelist()
                    # Check for PostgreSQL logs (typically in 'pgsql_log' folder or similar)
                    # We are looking for the ABSENCE of these files
                    # Adjust keywords based on actual structure, but 'pgsql' is standard for ManageEngine
                    has_db_logs = any('pgsql' in f.lower() or 'postgres' in f.lower() for f in file_list)
                    
                    if not has_db_logs:
                        db_excluded = True
                        score += 30
                        feedback_parts.append("Database logs successfully excluded.")
                    else:
                        feedback_parts.append("Database logs were found in the archive (should be excluded).")
            else:
                feedback_parts.append("Output file is not a valid zip archive.")
        except Exception as e:
            feedback_parts.append(f"Failed to inspect zip content: {e}")
        finally:
            if os.path.exists(temp_zip.name):
                os.unlink(temp_zip.name)
    
    # 4. VLM Verification (Visual Check)
    # Use trajectory frames to confirm navigation and interaction
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    # Add final shot to analysis list
    images_to_check = frames + ([final_shot] if final_shot else [])
    
    vlm_prompt = """
    Review these screenshots of a user interacting with ManageEngine ADAudit Plus.
    
    Verification Goals:
    1. Did the user navigate to the 'Support' tab or 'Support Information File' page?
    2. Did the user interact with checkboxes to exclude logs (specifically Database/PostgreSQL logs)?
    3. Did the user click a 'Generate' or 'Create' button?
    4. Is there a success message or a file listing showing a newly created support file?
    
    Respond in JSON:
    {
        "navigated_to_support": true/false,
        "excluded_db_logs_interaction": true/false,
        "generation_initiated": true/false,
        "success_indicator_visible": true/false
    }
    """
    
    vlm_score = 0
    if images_to_check:
        vlm_res = query_vlm(prompt=vlm_prompt, images=images_to_check)
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('navigated_to_support'):
                vlm_score += 10
            if parsed.get('excluded_db_logs_interaction'):
                vlm_score += 10
            if parsed.get('success_indicator_visible') or parsed.get('generation_initiated'):
                vlm_score += 10
                
            feedback_parts.append(f"VLM Analysis: Support page visited={parsed.get('navigated_to_support')}, DB log exclusion={parsed.get('excluded_db_logs_interaction')}.")
        else:
            feedback_parts.append("VLM analysis failed.")
    
    score += vlm_score

    # Final logic
    passed = score >= 80  # Requires file creation (40) + DB exclusion (30) + some VLM (10) OR full VLM
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }