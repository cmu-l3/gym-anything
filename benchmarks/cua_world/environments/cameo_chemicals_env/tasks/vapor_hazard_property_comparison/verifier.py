#!/usr/bin/env python3
"""
Verifier for vapor_hazard_property_comparison task.

Checks:
1. Report file existence and creation time.
2. Presence of all 4 required chemicals.
3. Identification of Acetone as the highest vapor hazard.
4. Plausible physical property values.
5. VLM verification of browsing history/trajectory.
"""

import json
import os
import base64
import re
import tempfile
import logging
from typing import Dict, Any, List

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import gym_anything VLM utils if available
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("gym_anything.vlm not available, VLM features might be limited")

def verify_vapor_hazard_report(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the vapor hazard report task.
    """
    # 1. Setup and data loading
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Decode report content
    content_b64 = result.get('file_content_base64', '')
    report_text = ""
    if content_b64:
        try:
            report_text = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
        except Exception:
            report_text = ""  # Failed to decode

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_chemicals = metadata.get('chemicals', ["Acetone", "Toluene", "Methanol", "Ethyl Acetate"])
    target_highest = metadata.get('target_highest_vapor_pressure', "Acetone")
    
    score = 0
    feedback = []
    
    # --- CHECK 1: File Existence & Creation (20 pts) ---
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 20
        feedback.append("Report file created successfully.")
    elif result.get('file_exists'):
        score += 10
        feedback.append("Report file exists but timestamp check failed (pre-existing?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not found."}

    if result.get('file_size', 0) < 50:
        feedback.append("File content is too short.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # --- CHECK 2: Content Analysis (40 pts) ---
    content_lower = report_text.lower()
    
    # 2a. Check for chemical names (10 pts)
    chemicals_found = 0
    for chem in expected_chemicals:
        if chem.lower() in content_lower:
            chemicals_found += 1
    
    if chemicals_found == 4:
        score += 10
        feedback.append("All 4 chemicals listed.")
    else:
        partial = int((chemicals_found / 4) * 10)
        score += partial
        feedback.append(f"Found {chemicals_found}/4 chemicals.")

    # 2b. Check for highest hazard identification (15 pts)
    # Looking for "Acetone" being linked to "high", "highest", "1", "first"
    # Simple heuristic: "Acetone" appears in a context suggesting it is the winner
    lines = report_text.splitlines()
    ranking_found = False
    correct_winner = False
    
    # Look for specific ranking section
    for line in lines:
        l = line.lower()
        if "highest" in l and target_highest.lower() in l:
            correct_winner = True
            break
        if "rank" in l or "order" in l:
            ranking_found = True
            # If Acetone is first in a list of chemicals on this or subsequent lines
            # This is hard to parse perfectly strictly, so we rely on the specific "Highest: Acetone" statement
            
    # Also check simplistic "1. Acetone" at start of lines if "Ranking" keyword exists
    if not correct_winner and ranking_found:
        for line in lines:
            if re.match(r"^\s*1[\.\)\s]+acetone", line, re.IGNORECASE):
                correct_winner = True
                break

    if correct_winner:
        score += 15
        feedback.append(f"Correctly identified {target_highest} as highest vapor hazard.")
    else:
        feedback.append(f"Failed to clearly identify {target_highest} as the highest hazard.")

    # 2c. check for data values (15 pts)
    # We look for numbers associated with Vapor Pressure terms
    # Just checking if the file contains numbers plausible for Vapor Pressure (e.g. >100 for Acetone)
    # Acetone VP is approx 180-240 mmHg depending on temp (20-25C)
    # Toluene is low (20-30)
    vp_keywords = ["vapor pressure", "vp", "mmHg", "kPa"]
    has_vp_data = any(k.lower() in content_lower for k in vp_keywords)
    
    # Rough check for the number 180-250 near "Acetone"
    acetone_data_ok = False
    if "acetone" in content_lower:
        # Find the block of text or line with Acetone
        # This is a loose check: do we see a number between 150 and 300 in the file?
        # A robust regex would be better but assumes formatting.
        if re.search(r"1[5-9]\d|2\d\d", content_lower): # Matches 150-299
            acetone_data_ok = True
            
    if has_vp_data and acetone_data_ok:
        score += 15
        feedback.append("Physical property data appears present and plausible.")
    elif has_vp_data:
        score += 10
        feedback.append("Physical property keywords found.")
    else:
        feedback.append("Missing vapor pressure data.")

    # --- CHECK 3: VLM Verification (40 pts) ---
    # We want to verify they actually used CAMEO Chemicals
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        # Get trajectory frames
        frames = []
        if VLM_AVAILABLE:
            frames = sample_trajectory_frames(traj, n=4)
        
        # Always include final screenshot
        final_shot = result.get('screenshot_path') # This path is inside container, we need the host one
        # The host one is in the trajectory or we can't easily get it if not passed in 'traj'.
        # Usually 'traj' contains the images.
        if not frames and 'frames' in traj:
            # Fallback if sample_trajectory_frames failed or empty
            import numpy as np
            f_indices = np.linspace(0, len(traj['frames']) - 1, 4, dtype=int)
            frames = [traj['frames'][i] for i in f_indices]

        if frames:
            prompt = """
            Review these screenshots of a user's workflow.
            1. Did the user visit the CAMEO Chemicals website (cameochemicals.noaa.gov)?
            2. Did they search for specific chemicals (Acetone, Toluene, etc.)?
            3. Did they view 'Chemical Datasheets' or 'Physical Properties' pages?
            
            Return JSON: {"cameo_visited": bool, "datasheets_viewed": bool, "confidence": float}
            """
            
            try:
                # We use the last frame or a collage. 
                # For this implementation, let's just use the last frame + one middle frame to save tokens/time if needed,
                # or pass list if supported. Assuming the tool supports list of images.
                vlm_resp = query_vlm(images=frames, prompt=prompt)
                
                if vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    if parsed.get("cameo_visited"):
                        vlm_score += 20
                        feedback.append("VLM confirmed CAMEO Chemicals usage.")
                    if parsed.get("datasheets_viewed"):
                        vlm_score += 20
                        feedback.append("VLM confirmed datasheet lookup.")
                else:
                    feedback.append("VLM verification failed to run.")
                    # Fallback: if file is good, give partial VLM points
                    if score >= 50: vlm_score += 20
            except Exception as e:
                logger.error(f"VLM error: {e}")
                if score >= 50: vlm_score += 20 # Grace points if technical error but file is good
        else:
             if score >= 50: vlm_score += 20 # Grace points
    else:
        # If VLM not available, re-weight or give free points if file is perfect
        if score >= 60:
            vlm_score = 40
            feedback.append("VLM skipped, full points awarded based on perfect output.")
        else:
            feedback.append("VLM skipped.")

    score += vlm_score

    # Final tally
    passed = (score >= 60) and result.get('file_created_during_task') and correct_winner
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }