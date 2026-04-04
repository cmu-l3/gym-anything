#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_antibiotic_screen(traj, env_info, task_info):
    """
    Verifies that the agent screened Methotrexate against 3 antibiotics.
    
    Scoring Logic:
    1. File Existence & Timing (20 pts): Output file created during task.
    2. Content Accuracy (40 pts): Correct drugs and valid interaction colors reported.
    3. VLM Trajectory (40 pts): Visual evidence of app usage (navigation to drugs).
    
    Pass Threshold: 70/100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Anti-Gaming (20 pts) ---
    if result_data.get("output_exists") and result_data.get("file_created_during_task"):
        score += 20
        feedback_parts.append("Report file created successfully.")
    elif result_data.get("output_exists"):
        score += 5
        feedback_parts.append("Report file exists but has old timestamp (anti-gaming fail).")
    else:
        feedback_parts.append("Report file not found.")

    # --- Criterion 2: Content Analysis (40 pts) ---
    # Expected format: "Amoxicillin: [Color]" ...
    raw_content = result_data.get("file_content", "").replace("|", "\n")
    content_lower = raw_content.lower()
    
    drugs_found = 0
    colors_valid = 0
    
    target_drugs = ["amoxicillin", "co-trimoxazole", "ciprofloxacin"]
    valid_colors = ["red", "orange", "yellow", "green", "grey"]
    
    lines = content_lower.split('\n')
    for drug in target_drugs:
        drug_line = next((line for line in lines if drug in line), None)
        if drug_line:
            drugs_found += 1
            # Check if a valid color is in the same line
            if any(color in drug_line for color in valid_colors):
                colors_valid += 1
    
    # Scoring for content
    # 3 drugs * 5 pts = 15 pts
    # 3 valid colors * 8.33 pts ~= 25 pts
    score += (drugs_found * 5)
    score += int(colors_valid * 8)
    
    if drugs_found < 3:
        feedback_parts.append(f"Missing drugs in report. Found: {drugs_found}/3.")
    if colors_valid < 3:
        feedback_parts.append(f"Invalid or missing colors in report. Valid entries: {colors_valid}/3.")
    else:
        feedback_parts.append("All drugs and interaction colors reported correctly.")

    # --- Criterion 3: VLM Trajectory Verification (40 pts) ---
    # We need to verify the agent actually navigated the app, not just halluncinated the file.
    frames = sample_trajectory_frames(traj, n=6)
    
    prompt = """
    You are auditing an agent using the 'Liverpool Cancer iChart' app.
    The goal was to check interactions for 'Methotrexate' with 'Amoxicillin', 'Co-trimoxazole', and 'Ciprofloxacin'.
    
    Review the sequence of screenshots.
    1. Do you see the 'Liverpool Cancer iChart' app open?
    2. Is 'Methotrexate' selected as the cancer drug at any point?
    3. Do you see navigation to 'Antibacterials' or a search for these specific antibiotics?
    4. Do you see interaction result screens (traffic lights) for any of these drugs?
    
    Return JSON:
    {
      "app_used": true,
      "methotrexate_selected": true,
      "antibiotics_checked": ["list", "drugs", "seen"],
      "interaction_screens_visible": true,
      "confidence": "high/medium/low"
    }
    """
    
    vlm_res = query_vlm(images=frames, prompt=prompt)
    vlm_data = vlm_res.get("parsed", {})
    
    vlm_score = 0
    if vlm_data.get("app_used"):
        vlm_score += 10
    if vlm_data.get("methotrexate_selected"):
        vlm_score += 10
    if vlm_data.get("interaction_screens_visible"):
        vlm_score += 20
        
    score += vlm_score
    feedback_parts.append(f"VLM verification score: {vlm_score}/40.")

    # --- Final Result ---
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }