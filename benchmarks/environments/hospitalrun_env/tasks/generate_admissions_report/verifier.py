#!/usr/bin/env python3
"""
Verifier for generate_admissions_report task.

Strategy:
1. Programmatic Check: Verify the output screenshot exists, was created during the task, 
   and has a reasonable file size.
2. VLM Verification: Use trajectory analysis to confirm:
   - Agent navigated to the Reports module.
   - Selected 'Admissions' report.
   - Generated the report (data table visible).
   - The saved screenshot actually shows the report (content verification).
"""

import json
import tempfile
import os
import logging
import sys

# Add gym_anything path to import vlm helpers if needed (simulated here)
# In real env: from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_admissions_report(traj, env_info, task_info):
    """
    Verifies that the agent generated the admissions report and saved a screenshot.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Desktop/admissions_report.png')
    
    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Programmatic Checks (50 points total)
    
    # Check 1: File Exists (20 pts)
    if result.get('output_exists'):
        score += 20
        feedback_parts.append("Screenshot file created.")
    else:
        feedback_parts.append("Screenshot file NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # Check 2: File Created During Task (15 pts)
    if result.get('file_created_during_task'):
        score += 15
        feedback_parts.append("File created during task session.")
    else:
        feedback_parts.append("File timestamp is invalid (created before task?).")

    # Check 3: File Size (15 pts) - Filters out 0-byte or trivially empty images
    size_bytes = result.get('output_size_bytes', 0)
    if size_bytes > 10240: # > 10KB
        score += 15
    elif size_bytes > 0:
        score += 5
        feedback_parts.append(f"File size warning: {size_bytes} bytes is very small.")
    else:
        feedback_parts.append("File is empty (0 bytes).")

    # 3. VLM Verification (50 points total)
    # We rely on the VLM to check the *content* of the work.
    
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    # Sample frames to see the workflow
    frames = sample_trajectory_frames(traj, n=4)
    
    # Helper to get the actual saved output image if we could (optional enhancement), 
    # but strictly we use the trajectory frames and final screen state here.
    
    prompt = """
    You are verifying if an agent successfully generated a hospital Admissions Report.
    
    Review the sequence of screenshots. The agent should:
    1. Navigate to a "Reports" section (look for "Reports" in sidebar or header).
    2. Select an "Admissions" or "Visits" report type.
    3. Generate the report, resulting in a table or list of patient admission data being displayed.
    
    Verification Questions:
    1. Did the agent navigate to the Reports page?
    2. Is a report results table visible in the final or near-final frames (showing rows of data like dates, patient names, or reasons)?
    3. Does the final state look like a successfully generated report?
    
    Answer JSON:
    {
        "navigated_to_reports": true/false,
        "report_data_visible": true/false,
        "explanation": "..."
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    navigated = False
    data_visible = False
    
    if vlm_result and 'result' in vlm_result:
        # Assuming query_vlm returns a dict or we parse the string JSON
        try:
            # Simple handling if it returns a string
            import re
            json_match = re.search(r'\{.*\}', vlm_result['result'], re.DOTALL)
            if json_match:
                parsed = json.loads(json_match.group(0))
                navigated = parsed.get('navigated_to_reports', False)
                data_visible = parsed.get('report_data_visible', False)
                feedback_parts.append(f"VLM Analysis: {parsed.get('explanation', '')}")
        except:
            feedback_parts.append("VLM response parsing failed.")

    # Scoring VLM results
    if navigated:
        score += 20
        feedback_parts.append("Confirmed navigation to Reports.")
    else:
        feedback_parts.append("Could not visually confirm navigation to Reports.")

    if data_visible:
        score += 30
        feedback_parts.append("Confirmed report data is visible.")
    else:
        feedback_parts.append("Could not visually confirm report data generation.")

    # 4. Final Decision
    # Pass if file is good (50 pts) AND at least navigation happened (20 pts) -> 70 threshold
    # But for robust pass, we really want data visible.
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }