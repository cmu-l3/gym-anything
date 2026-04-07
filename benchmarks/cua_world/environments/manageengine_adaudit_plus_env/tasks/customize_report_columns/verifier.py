#!/usr/bin/env python3
"""
Verifier for customize_report_columns task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_report_columns(traj, env_info, task_info):
    """
    Verifies that the agent customized the report columns correctly.
    
    Strategies:
    1. Check if the agent created the specific screenshot requested (custom_columns.png).
    2. Use VLM to inspect that screenshot for required/forbidden headers.
    3. Fallback: Inspect the final state screenshot if specific one is missing.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Define paths (Windows paths in container, mapped to temp local paths)
    # Note: copy_from_env source paths should match what's in the container
    container_result_path = "C:/workspace/task_result.json"
    container_screenshot_path = "C:/workspace/custom_columns.png"
    container_final_screen_path = "C:/workspace/task_final.png"
    
    # Load task metadata
    metadata = task_info.get('metadata', {})
    required_columns = metadata.get('required_columns', ["User Name", "Client IP Address", "Failure Reason", "Logon Time"])
    forbidden_columns = metadata.get('forbidden_columns', ["Domain Name", "Logon Type"])
    
    # Helper to copy files
    def fetch_file(src_path):
        if not src_path: return None
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(src_path)[1])
            tmp.close()
            copy_from_env(src_path, tmp.name)
            return tmp.name
        except Exception:
            return None

    # Load Result JSON
    result_json_path = fetch_file(container_result_path)
    if not result_json_path:
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result file."}
    
    try:
        with open(result_json_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {str(e)}"}
    finally:
        os.unlink(result_json_path)

    # 2. Get Images for Verification
    # Prefer the specific screenshot the agent was asked to take
    image_to_check = None
    source_type = "none"
    
    if task_result.get("screenshot_exists") and task_result.get("screenshot_created_during_task"):
        image_to_check = fetch_file(container_screenshot_path)
        source_type = "agent_screenshot"
    
    # Fallback to final state screenshot
    if not image_to_check:
        image_to_check = fetch_file(container_final_screen_path)
        source_type = "final_state"

    if not image_to_check:
        return {"passed": False, "score": 0, "feedback": "No visual evidence found (screenshots missing)."}

    # 3. VLM Verification
    # We use the 'query_vlm' function which should be available in the global scope or imported
    # Assuming standard gym_anything VLM interface
    from gym_anything.vlm import query_vlm

    prompt = f"""
    You are verifying a UI task in ManageEngine ADAudit Plus.
    The user was asked to customize the "User Logon Failures" report columns.
    
    Look at the image (which shows a report grid/table).
    
    1. Search for these Column Headers (MUST be present):
       {', '.join(required_columns)}
       
    2. Search for these Column Headers (MUST BE ABSENT/HIDDEN):
       {', '.join(forbidden_columns)}
       
    Answer in JSON:
    {{
        "visible_columns": ["list", "of", "all", "columns", "seen"],
        "required_found": ["list", "of", "required", "columns", "found"],
        "forbidden_found": ["list", "of", "forbidden", "columns", "found"],
        "is_report_grid_visible": true/false
    }}
    """

    try:
        vlm_resp = query_vlm(prompt=prompt, image=image_to_check)
        parsed = vlm_resp.get("parsed", {})
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"VLM verification failed: {str(e)}"}
    finally:
        if image_to_check: os.unlink(image_to_check)

    # 4. Scoring Logic
    score = 0
    feedback_lines = []

    # Criterion 1: Report Grid Visible (20 pts)
    if parsed.get("is_report_grid_visible"):
        score += 20
        feedback_lines.append("Report grid is visible.")
    else:
        feedback_lines.append("Report grid not detected.")

    # Criterion 2: Required Columns (10 pts each)
    found_req = parsed.get("required_found", [])
    for col in required_columns:
        # Fuzzy match check can be added here if VLM is imprecise, but assuming direct match for now
        if any(col.lower() in f.lower() for f in found_req):
            score += 10
            feedback_lines.append(f"Found required column: {col}")
        else:
            feedback_lines.append(f"Missing required column: {col}")

    # Criterion 3: Forbidden Columns (10 pts each for NOT being there)
    found_forbid = parsed.get("forbidden_found", [])
    for col in forbidden_columns:
        if not any(col.lower() in f.lower() for f in found_forbid):
            score += 10
            feedback_lines.append(f"Correctly hidden column: {col}")
        else:
            feedback_lines.append(f"Forbidden column still visible: {col}")

    # Criterion 4: Evidence Creation (20 pts)
    # Did they create the file requested?
    if source_type == "agent_screenshot":
        score += 20
        feedback_lines.append("Agent correctly saved the evidence screenshot.")
    else:
        feedback_lines.append("Agent did not save the requested screenshot (used final state fallback).")

    # Pass/Fail
    # Max score: 20 + (4*10) + (2*10) + 20 = 100
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }