#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bom_to_lci_model(traj, env_info, task_info):
    """
    Verifies the BOM to LCI Model task.
    
    Criteria:
    1. Output CSV exists and has content (20 pts)
    2. Process 'Electric Kettle Manufacturing' exists in DB (20 pts)
    3. Process has correct number of inputs (approx 5) (20 pts)
    4. Inputs are explicitly linked to providers (anti-gaming for just typing text) (20 pts)
    5. VLM verification of workflow (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Load programmatic result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Output CSV (20 pts)
    if result.get("output_file_exists") and result.get("output_file_new"):
        size = result.get("output_file_size", 0)
        if size > 100:
            score += 20
            feedback.append("Result CSV exported successfully.")
        else:
            score += 10
            feedback.append("Result CSV exists but is very small/empty.")
    else:
        feedback.append("Result CSV not found or not created during task.")

    # 2. Process Existence (20 pts)
    if result.get("db_process_found"):
        score += 20
        feedback.append("Process 'Electric Kettle Manufacturing' found in database.")
    else:
        feedback.append("Process 'Electric Kettle Manufacturing' NOT found in database.")

    # 3. Exchange Count (20 pts)
    # BOM has 5 items. Allow +/- 1 for potential output flow or slight variations.
    count = int(result.get("exchange_count", 0))
    # Usually 5 inputs + 1 output = 6 exchanges, or just inputs. 
    # If agent configured correctly, should be at least 5.
    if count >= 5:
        score += 20
        feedback.append(f"Correct number of exchanges found ({count}).")
    elif count > 0:
        score += 10
        feedback.append(f"Partial exchanges found ({count}/5 expected inputs).")
    else:
        feedback.append("No exchanges found in process.")

    # 4. Provider Linking (20 pts)
    # The task specifically asks to link providers. 
    # Unlinked exchanges have NULL provider IDs.
    linked = int(result.get("linked_provider_count", 0))
    if linked >= 4: # Allow 1 miss
        score += 20
        feedback.append("Inputs are correctly linked to providers.")
    elif linked > 0:
        score += 10
        feedback.append(f"Some inputs linked ({linked}), others missing providers.")
    else:
        feedback.append("No inputs are linked to providers (Provider column empty).")

    # 5. VLM Verification (20 pts)
    # Check for visual evidence of BOM usage and linking
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_scr = get_final_screenshot(traj)
        
        prompt = """
        You are verifying an OpenLCA task. The user was supposed to:
        1. Create a process named 'Electric Kettle Manufacturing'.
        2. Read a BOM CSV file.
        3. Add inputs like 'Polypropylene', 'Steel', 'Copper', 'Electricity'.
        4. Link these inputs to providers (the Provider column in OpenLCA should not be empty).
        
        Look at the screenshots.
        - Do you see the 'Electric Kettle Manufacturing' process editor?
        - Do you see a list of inputs/exchanges?
        - Are there names like Polypropylene, Steel, or Copper visible in the inputs?
        - In the 'Provider' column of the inputs table, are there values selected (text inside the box) or is it empty/None?
        
        Return JSON: {"process_seen": bool, "inputs_match_bom": bool, "providers_linked": bool}
        """
        
        vlm_res = query_vlm(prompt=prompt, images=frames + [final_scr])
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("process_seen"): vlm_score += 5
            if parsed.get("inputs_match_bom"): vlm_score += 10
            if parsed.get("providers_linked"): vlm_score += 5
            feedback.append(f"VLM verification score: {vlm_score}/20")
        else:
            feedback.append("VLM check failed to run.")
            vlm_score = 10 # Grace points if VLM fails but programmatic passed
            
    except Exception as e:
        logger.warning(f"VLM Exception: {e}")
        vlm_score = 0

    score += vlm_score

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }