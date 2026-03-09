#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_screen_admission_meds(traj, env_info, task_info):
    """
    Verifies that the agent screened the 4 specific drugs against Ceritinib.
    
    Criteria:
    1. File /sdcard/ceritinib_screening_report.txt exists and was created during task.
    2. File contains all 4 required drugs (Rifampicin, Warfarin, Midazolam, Metformin).
    3. File contains valid traffic light colors for each.
    4. VLM Trajectory confirms "Ceritinib" was the selected cancer drug.
    5. VLM Trajectory confirms navigation to the interaction list.
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_drugs = set(d.lower() for d in metadata.get('required_drugs', []))
    valid_colors = set(c.lower() for c in metadata.get('valid_colors', []))
    
    # Helper to clean up temp files
    temp_files = []
    
    try:
        # Retrieve JSON result
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_files.append(temp_json.name)
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        for tf in temp_files:
            if os.path.exists(tf):
                os.unlink(tf)

    # 2. File Verification (50 points)
    score = 0
    feedback = []
    
    file_content = result_data.get("file_content", "")
    file_exists = result_data.get("file_exists", False)
    created_during = result_data.get("file_created_during_task", False)
    
    if not file_exists:
        feedback.append("Report file not found.")
    elif not created_during:
        feedback.append("Report file exists but was not created during this task session.")
    else:
        score += 10
        feedback.append("Report file created successfully.")
        
        # Parse content
        # Expected format: Drug,Color
        lines = [line.strip() for line in file_content.split('\\n') if line.strip()]
        found_drugs = {}
        
        for line in lines:
            parts = line.split(',')
            if len(parts) >= 2:
                drug = parts[0].strip().lower()
                color = parts[1].strip().lower()
                if drug in required_drugs:
                    found_drugs[drug] = color
        
        # Check completeness
        missing = required_drugs - set(found_drugs.keys())
        if not missing:
            score += 20
            feedback.append("All 4 required drugs found in report.")
        else:
            partial = 20 * (len(found_drugs) / 4)
            score += partial
            feedback.append(f"Missing drugs in report: {', '.join(missing)}")
            
        # Check color validity & accuracy (Simple validity check)
        valid_entries = 0
        for d, c in found_drugs.items():
            if c in valid_colors:
                valid_entries += 1
            else:
                feedback.append(f"Invalid color '{c}' for {d}")
        
        score += (valid_entries / 4) * 20
        feedback.append(f"{valid_entries}/4 drugs have valid color formats.")

    # 3. VLM Trajectory Verification (50 points)
    # We need to confirm they actually looked up "Ceritinib"
    
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    You are verifying an agent's workflow in the 'Liverpool Cancer iChart' app.
    The agent was supposed to:
    1. Select the cancer drug 'Ceritinib'.
    2. Look up interactions for Rifampicin, Warfarin, Midazolam, and Metformin.
    
    Look at the sequence of screenshots.
    
    Question 1: Is 'Ceritinib' visible as the selected/active cancer drug in the header or list in ANY frame?
    Question 2: Do you see lists of medications or interaction result screens (Red/Orange/Green/Yellow banners)?
    
    Answer JSON:
    {
        "ceritinib_selected": boolean,
        "interaction_screens_visible": boolean,
        "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
    
    ceritinib_confirmed = False
    interactions_confirmed = False
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        ceritinib_confirmed = parsed.get('ceritinib_selected', False)
        interactions_confirmed = parsed.get('interaction_screens_visible', False)
        
        if ceritinib_confirmed:
            score += 25
            feedback.append("VLM confirmed 'Ceritinib' was selected.")
        else:
            feedback.append("VLM could not find visual evidence of 'Ceritinib' selection.")
            
        if interactions_confirmed:
            score += 25
            feedback.append("VLM confirmed interaction screens were visited.")
        else:
            feedback.append("VLM could not find evidence of interaction result screens.")
    else:
        feedback.append("VLM verification failed to execute.")

    # 4. Final Scoring
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }