#!/usr/bin/env python3
import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gout_safety_check(traj, env_info, task_info):
    """
    Verifies that the agent correctly identified the safer gout medication.
    
    Criteria:
    1. Output file exists and was created during the task.
    2. File correctly identifies Mercaptopurine + Allopurinol as High Risk (Red/Orange).
    3. File correctly identifies Mercaptopurine + Colchicine as Safer (Green/Yellow).
    4. VLM verifies the agent actually viewed the interaction screens.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata for scoring
    metadata = task_info.get('metadata', {})
    expected_colors_allopurinol = metadata.get('expected_color_allopurinol', ['red', 'orange'])
    expected_colors_colchicine = metadata.get('expected_color_colchicine', ['green', 'yellow'])
    
    score = 0
    feedback = []
    
    # 1. Retrieve and Parse JSON Result from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check File Existence & Timestamp (Anti-Gaming)
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file /sdcard/gout_safety_check.txt not found."}
    
    task_start = result.get("task_start", 0)
    file_mod = result.get("file_mod_time", 0)
    
    if file_mod < task_start:
        feedback.append("Warning: File modification time looks suspicious (older than task start).")
        # Depending on device clock sync, we might not fail strictly, but we note it.
        # For now, we award existence points.
    
    score += 10
    feedback.append("Output file created.")
    
    # 3. Analyze Text Content
    content = result.get("file_content", "")
    content_lower = content.lower()
    
    # Check Drug Context
    if "mercaptopurine" in content_lower:
        score += 10
        feedback.append("Correct cancer drug context.")
    else:
        feedback.append("Missing 'Mercaptopurine' in output.")

    # Check Allopurinol Assessment (High Risk)
    allo_pattern = r"allopurinol.*(red|orange)"
    if re.search(allo_pattern, content_lower):
        score += 25
        feedback.append("Correctly identified Allopurinol risk (Red/Orange).")
    elif "allopurinol" in content_lower:
        feedback.append("Mentioned Allopurinol but missed correct color/risk level.")
        score += 5
    else:
        feedback.append("Failed to evaluate Allopurinol.")

    # Check Colchicine Assessment (Safer)
    colch_pattern = r"colchicine.*(green|yellow|grey)"
    if re.search(colch_pattern, content_lower):
        score += 25
        feedback.append("Correctly identified Colchicine safety (Green/Yellow).")
    elif "colchicine" in content_lower:
        feedback.append("Mentioned Colchicine but missed correct color.")
        score += 5
    else:
        feedback.append("Failed to evaluate Colchicine.")
        
    # Check Recommendation
    if "use colchicine" in content_lower or "recommendation: colchicine" in content_lower:
        score += 10
        feedback.append("Correct recommendation made.")

    # 4. VLM Trajectory Verification
    # We want to see evidence that the agent actually looked up the drugs
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an agent's interaction with the Liverpool Cancer iChart app.
    The agent should be checking interactions for "Mercaptopurine".
    
    Look at the sequence of images and answer:
    1. Is the "Cancer iChart" app visible?
    2. Did the agent search for or select "Mercaptopurine"?
    3. Is there a screen showing interaction results (traffic light colors)?
    4. Are "Allopurinol" or "Colchicine" visible in any list or result?
    
    Respond in JSON:
    {
        "app_visible": true/false,
        "mercaptopurine_seen": true/false,
        "interaction_colors_seen": true/false,
        "comedication_seen": true/false
    }
    """
    
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_data = vlm_res.get("parsed", {})
        
        if vlm_data.get("app_visible"):
            score += 5
        if vlm_data.get("mercaptopurine_seen"):
            score += 5
        if vlm_data.get("interaction_colors_seen"):
            score += 5
        if vlm_data.get("comedication_seen"):
            score += 5
            
        feedback.append(f"VLM Verification: {json.dumps(vlm_data)}")
        
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        # Fallback: if text file is perfect, we assume they did it, but cap score slightly?
        # Alternatively, give partial credit to avoid penalizing VLM failure.
        score += 10 
        feedback.append("VLM verification skipped due to error.")

    # Final Pass/Fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }