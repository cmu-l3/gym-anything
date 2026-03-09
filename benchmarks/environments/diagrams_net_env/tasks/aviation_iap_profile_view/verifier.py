#!/usr/bin/env python3
import json
import os
import sys
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_aviation_iap_profile_view(traj, env_info, task_info):
    """
    Verifies the Aviation IAP Profile View task.
    Checks:
    1. Output files creation (XML & PDF).
    2. Presence of key aeronautical text labels.
    3. Correct vertical topology (ARCHI above DUMBA above RWY).
    4. VLM verification for visual correctness (dashed lines, schematic style).
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy unavailable"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 2. Programmatic Verification (60 points)
    
    # File Existence (10 pts)
    if result_data.get('drawio_exists') and result_data.get('pdf_exists'):
        score += 10
        feedback.append("Files created successfully.")
    else:
        feedback.append("Missing .drawio or .pdf output files.")

    # Content Analysis (from XML)
    content = result_data.get('content_analysis', {})
    
    # Text Labels (20 pts)
    required_texts = [
        ('archi_found', 'ARCHI'),
        ('dumba_found', 'DUMBA'),
        ('alt_4000_found', '4000'),
        ('alt_1800_found', '1800'),
        ('freq_found', '111.7')
    ]
    
    found_count = sum(1 for key, _ in required_texts if content.get(key))
    if found_count == len(required_texts):
        score += 20
        feedback.append(f"All {len(required_texts)} required text labels found.")
    elif found_count > 0:
        partial = int((found_count / len(required_texts)) * 20)
        score += partial
        feedback.append(f"Found {found_count}/{len(required_texts)} text labels.")
    else:
        feedback.append("No required text labels found in diagram.")

    # Vertical Topology Check (20 pts)
    # In screen coordinates, Top=0. So Higher Altitude = Lower Y value.
    # Expected: Y_ARCHI < Y_DUMBA < Y_RWY
    y_archi = content.get('archi_y', 10000)
    y_dumba = content.get('dumba_y', 10000)
    y_rwy = content.get('rwy_y', 0)
    
    # Note: If defaults remain (10000 or 0), the check fails naturally
    topology_pass = False
    if y_archi < y_dumba and y_dumba < y_rwy:
        topology_pass = True
        score += 20
        feedback.append("Vertical topology correct (ARCHI > DUMBA > RWY).")
    else:
        feedback.append(f"Vertical topology incorrect or shapes not found (Y_ARCHI={y_archi}, Y_DUMBA={y_dumba}, Y_RWY={y_rwy}).")

    # Dashed Line (Missed Approach) Programmatic Check (10 pts)
    if content.get('has_dashed_line'):
        score += 10
        feedback.append("Dashed line style detected (Missed Approach).")
    else:
        feedback.append("No dashed line style detected.")

    # 3. VLM Verification (40 points)
    # Visual check for the specific "Profile View" structure which is hard to fully verify via XML
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        vlm_prompt = """
        You are an aviation chart verifier. Look at this diagrams.net workspace.
        The user is supposed to be drawing an Instrument Approach 'Profile View'.
        
        Check for these specific visual elements:
        1. A schematic side-view diagram (not a top-down map).
        2. A descent path that looks like steps or a slope going down from left to right.
        3. A "Glideslope" wedge or angle symbol (often a long triangle pointing to the runway).
        4. A dashed arrow curving UPWARDS at the end (Missed Approach).
        5. "Maltese Cross" or similar symbol at the FAF (Final Approach Fix).
        
        Does the diagram look like a valid aviation profile view?
        """
        
        try:
            vlm_response = query_vlm(prompt=vlm_prompt, images=frames + [final_screen])
            vlm_score = 0
            
            # Simple heuristic analysis of VLM text response
            lower_resp = vlm_response.get('text', '').lower()
            
            if "profile view" in lower_resp or "side-view" in lower_resp:
                vlm_score += 10
            if "descent" in lower_resp or "slope" in lower_resp:
                vlm_score += 10
            if "dashed" in lower_resp or "missed approach" in lower_resp:
                vlm_score += 10
            if "glideslope" in lower_resp or "wedge" in lower_resp:
                vlm_score += 10
                
            score += vlm_score
            feedback.append(f"VLM visual verification score: {vlm_score}/40")
            
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if programmatic topology passed, give partial VLM credit
            if topology_pass:
                score += 20
                feedback.append("VLM failed, awarding partial credit based on topology pass.")

    # 4. Final Scoring
    passed = score >= 65 and topology_pass
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }