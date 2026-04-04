#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from datetime import datetime, timedelta
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_multiday_pass(traj, env_info, task_info):
    """
    Verifies that the agent registered visitor 'Elena Rosales' with a 14-day expiration.
    
    Strategy:
    1. Check for existence of a newly created proof file (screenshot or export).
    2. Use VLM to analyze the proof file AND trajectory frames.
       - Look for Name, Company, and specifically the Expiration Date.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_name = metadata.get('visitor_name', "Elena Rosales")
    target_company = metadata.get('company_name', "Apex Structural")
    
    # Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    proof_found = result_data.get("proof_found", False)
    proof_path = result_data.get("proof_path", "")
    target_date_str = result_data.get("target_expiration_str", "") # YYYY-MM-DD
    
    # Calculate target date formats for flexible VLM matching
    # Example: if target is 2024-01-15, look for "1/15", "Jan 15", "15-Jan", etc.
    try:
        dt = datetime.strptime(target_date_str, "%Y-%m-%d")
        date_formats = [
            dt.strftime("%m/%d/%Y"), # 01/15/2024
            dt.strftime("%-m/%-d/%Y"), # 1/15/2024
            dt.strftime("%b %d"),    # Jan 15
            dt.strftime("%d %b"),    # 15 Jan
            dt.strftime("%Y-%m-%d")  # 2024-01-15
        ]
        target_day = str(dt.day) # Just the day number (e.g. "15") is a weak signal but useful context
    except:
        date_formats = []
        target_day = "99"

    score = 0
    feedback = []

    # 2. Score: Proof File Existence (20 pts)
    if proof_found:
        score += 20
        feedback.append("Proof file created successfully.")
        
        # Retrieve the proof file for VLM analysis
        local_proof = tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(proof_path)[1])
        try:
            copy_from_env(proof_path, local_proof.name)
            proof_image_path = local_proof.name
        except:
            proof_image_path = None
            feedback.append("Warning: Could not retrieve proof file content.")
    else:
        feedback.append("No proof file (screenshot/export) found in Documents.")
        proof_image_path = None

    # 3. VLM Verification (80 pts)
    # We analyze the user-generated proof file (if exists) AND trajectory frames
    # to catch the moment they set the date.
    
    images_to_analyze = []
    
    # Add proof file if it's an image
    if proof_image_path and proof_path.endswith('.png'):
        images_to_analyze.append(proof_image_path)
    
    # Add trajectory frames (essential if proof is text file or missing)
    traj_frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    # If we have a proof image, prioritize it, otherwise rely on trajectory
    if not images_to_analyze:
        images_to_analyze = [final_shot] + traj_frames
    
    prompt = f"""
    Analyze these images of the Jolly Lobby Track visitor software.
    I am verifying if a visitor was registered correctly with a specific expiration date.
    
    Target Information:
    1. Name: {target_name}
    2. Company: {target_company}
    3. Expiration/Valid-Until Date: Approximately {target_date_str} (or {', '.join(date_formats[:2])})
    
    Look for:
    - A form field or table row showing "{target_name}".
    - A date field labeled "Expiration", "Valid To", "Departure", or similar that matches the target date.
    - The company "{target_company}".
    
    Return JSON:
    {{
        "name_visible": true/false,
        "company_visible": true/false,
        "expiration_date_visible": true/false,
        "observed_date": "string found or null",
        "confidence": "low/medium/high"
    }}
    """
    
    vlm_result = query_vlm(images=images_to_analyze, prompt=prompt)
    
    if vlm_result['success']:
        parsed = vlm_result.get('parsed', {})
        
        # Name Check (20 pts)
        if parsed.get('name_visible'):
            score += 20
            feedback.append(f"VLM confirmed visitor name '{target_name}'.")
        else:
            feedback.append(f"VLM could not find name '{target_name}'.")
            
        # Company Check (10 pts)
        if parsed.get('company_visible'):
            score += 10
            feedback.append(f"VLM confirmed company '{target_company}'.")
        
        # Date Check (50 pts) - heavily weighted as it's the core "logic" of the task
        if parsed.get('expiration_date_visible'):
            score += 50
            feedback.append("VLM confirmed correct expiration date set.")
        else:
            # Partial credit if they made the file but date is unclear
            if proof_found:
                 feedback.append("VLM could not clearly read the expiration date.")
            else:
                 feedback.append("VLM could not find evidence of expiration date setting.")
    else:
        feedback.append("VLM analysis failed.")

    # Cleanup
    if proof_image_path and os.path.exists(proof_image_path):
        os.unlink(proof_image_path)

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }