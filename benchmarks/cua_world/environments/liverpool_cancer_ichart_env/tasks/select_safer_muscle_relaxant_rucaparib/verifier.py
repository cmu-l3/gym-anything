#!/usr/bin/env python3
"""
Verifier for select_safer_muscle_relaxant_rucaparib@1
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_muscle_relaxant_safety(traj, env_info, task_info):
    """
    Verifies the muscle relaxant safety comparison task.
    
    Criteria:
    1. Report file exists and was created during task.
    2. Tizanidine is identified as Red/Orange (Risk).
    3. Baclofen is identified as Green/Grey (Safe).
    4. "Safer Choice" explicitly names Baclofen.
    5. VLM: Trajectory shows navigation to Rucaparib and the relevant co-meds.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    
    # Files to retrieve from the Android environment
    # Note: The export script created these on /sdcard inside the emulator.
    # The `copy_from_env` implementation for Android environments typically handles
    # `adb pull` under the hood if given an absolute path like /sdcard/...
    # If not, standard path mapping applies. assuming standard behavior here.
    
    # We need to copy the JSON result file
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
    
    # --- Check 1: File Existence & Anti-Gaming (15 pts) ---
    if not result_data.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Result file /sdcard/muscle_relaxant_safety.txt not found."}
    
    if not result_data.get("created_during_task", False):
        feedback_parts.append("File timestamp indicates it was not created during this session.")
    else:
        score += 15
        feedback_parts.append("Report file created successfully.")

    content = result_data.get("file_content", "")
    logger.info(f"Agent content: {content}")

    # --- Check 2: Content Analysis (60 pts) ---
    # Expected format:
    # Rucaparib + Tizanidine: [COLOR]
    # Rucaparib + Baclofen: [COLOR]
    # Safer Choice: [DRUG_NAME]

    # Normalize content
    content_lower = content.lower()
    
    # 2a. Tizanidine Check (20 pts)
    # Rucaparib (CYP1A2 inhibitor) + Tizanidine (CYP1A2 substrate) -> RED or ORANGE
    tiz_match = re.search(r"tizanidine.*:.*(red|orange)", content_lower)
    if tiz_match:
        score += 20
        feedback_parts.append("Correctly identified Tizanidine risk (Red/Orange).")
    else:
        feedback_parts.append("Failed to correctly identify Tizanidine interaction color (Expected Red or Orange).")

    # 2b. Baclofen Check (20 pts)
    # Rucaparib + Baclofen (Renal) -> GREEN or GREY
    bac_match = re.search(r"baclofen.*:.*(green|grey|gray)", content_lower)
    if bac_match:
        score += 20
        feedback_parts.append("Correctly identified Baclofen safety (Green/Grey).")
    else:
        feedback_parts.append("Failed to correctly identify Baclofen interaction color (Expected Green or Grey).")

    # 2c. Recommendation Check (20 pts)
    # Must explicitly say Baclofen is safer
    safe_match = re.search(r"safer.*:.*baclofen", content_lower)
    if safe_match:
        score += 20
        feedback_parts.append("Correctly recommended Baclofen as the safer choice.")
    else:
        feedback_parts.append("Did not correctly state 'Baclofen' as the safer choice in the final line.")

    # --- Check 3: VLM Trajectory Verification (25 pts) ---
    # Use VLM to confirm the agent actually looked at the app
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    Review these screenshots of an agent using the Liverpool Cancer iChart app.
    The agent should be checking interactions for Rucaparib.
    
    Look for:
    1. The drug "Rucaparib" being selected or visible in the header.
    2. A list of "Muscle Relaxants" or "Musculoskeletal" drugs.
    3. Interaction results (traffic lights) for Tizanidine or Baclofen.
    
    Did the agent perform the search?
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_passed = False
    if vlm_result and vlm_result.get("success"):
        # We assume the VLM returns a boolean 'yes'/'no' or we parse the reasoning
        # For this template, we'll check if the VLM response suggests positive confirmation
        parsed = vlm_result.get("parsed", {})
        # Simple heuristic on text response if parsed isn't structured
        response_text = vlm_result.get("response", "").lower()
        if "yes" in response_text or "perform the search" in response_text or "visible" in response_text:
            vlm_passed = True
    
    if vlm_passed:
        score += 25
        feedback_parts.append("Visual verification confirmed search workflow.")
    else:
        feedback_parts.append("Visual verification could not confirm the search workflow.")

    # Final Pass Logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }