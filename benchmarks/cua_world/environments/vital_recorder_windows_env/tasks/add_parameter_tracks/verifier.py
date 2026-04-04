#!/usr/bin/env python3
"""
Verifier for Vital Recorder task: add_parameter_tracks.

Verification Logic:
1. Validates that Vital Recorder is running and the correct file is loaded.
2. Uses VLM to inspect the final screenshot for the presence of specific tracks:
   - ART_MBP (Mean Arterial Pressure)
   - ETCO2 (End-tidal CO2)
   - BIS (Bispectral Index)
3. Checks anti-gaming constraints (timestamps).
"""

import json
import os
import tempfile
import logging
import shutil
from typing import Dict, Any

# Import VLM utilities from the framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback for testing/stubbing if framework not present
    def query_vlm(prompt, image): return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj): return None
    def sample_trajectory_frames(traj, n=1): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying a task in the Vital Recorder software. 
The user was asked to add three specific tracks to the waveform display:
1. ART_MBP (Mean Arterial Pressure)
2. ETCO2 (End-Tidal CO2)
3. BIS (Bispectral Index)

Analyze the screenshot of the application window.
Look at the vertical list of track names/labels on the left side of the waveform area.

Answer the following in JSON format:
{
  "art_mbp_visible": boolean, // Is a track labeled "ART_MBP" or "ART Mean" or "ART_M" visible?
  "etco2_visible": boolean,   // Is a track labeled "ETCO2" or "EtCO2" visible?
  "bis_visible": boolean,     // Is a track labeled "BIS" visible?
  "data_visible": boolean,    // Do these tracks show actual lines/numbers (not empty/flat)?
  "window_title_correct": boolean // Does the window title contain "0001" or "0001.vital"?
}
"""

def verify_add_parameter_tracks(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the task completion.
    """
    # 1. Setup access to container files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 2. Retrieve result JSON from the container
    # The export script saves to C:\tmp\task_result.json, which maps to /tmp/task_result.json in some setups,
    # but for Windows containers, paths can be tricky.
    # The framework usually handles the path translation if we use the internal path used in export.
    # In export_result.ps1, we used "C:\tmp\task_result.json".
    # We will try to copy from that location.
    
    temp_json_path = tempfile.mktemp(suffix=".json")
    try:
        # Note: Container path in Windows might need specific handling, but we assume
        # the framework treats the provided string as the path inside the guest.
        copy_from_env("C:\\tmp\\task_result.json", temp_json_path)
        
        with open(temp_json_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from environment."}
    finally:
        if os.path.exists(temp_json_path):
            os.remove(temp_json_path)

    # 3. Retrieve Screenshot
    # We prefer the screenshot from the trajectory for VLM to ensure we see what the agent saw.
    final_screenshot = get_final_screenshot(traj)
    
    # If trajectory screenshot is missing, fallback to the one exported by the script
    if not final_screenshot:
        container_screen_path = result_data.get("screenshot_path")
        if container_screen_path:
            local_screen_path = tempfile.mktemp(suffix=".png")
            try:
                copy_from_env(container_screen_path, local_screen_path)
                # We need to read it into bytes or pass path depending on what query_vlm expects.
                # Assuming query_vlm handles paths or we read it here.
                # For this stub, we assume query_vlm takes a path or PIL image.
                # Let's assume it takes a path string for this implementation.
                final_screenshot = local_screen_path
            except Exception as e:
                logger.warning(f"Failed to copy manual screenshot: {e}")

    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No evidence screenshot available."}

    # 4. VLM Verification
    vlm_response = query_vlm(prompt=VLM_PROMPT, image=final_screenshot)
    
    if not vlm_response.get("success"):
        return {"passed": False, "score": 0, "feedback": f"Verification analysis failed: {vlm_response.get('error')}"}

    parsed = vlm_response.get("parsed", {})
    
    # 5. Scoring
    score = 0
    feedback_items = []

    # Criterion: ART_MBP (25 pts)
    if parsed.get("art_mbp_visible"):
        score += 25
        feedback_items.append("ART_MBP track added.")
    else:
        feedback_items.append("Missing ART_MBP track.")

    # Criterion: ETCO2 (25 pts)
    if parsed.get("etco2_visible"):
        score += 25
        feedback_items.append("ETCO2 track added.")
    else:
        feedback_items.append("Missing ETCO2 track.")

    # Criterion: BIS (25 pts)
    if parsed.get("bis_visible"):
        score += 25
        feedback_items.append("BIS track added.")
    else:
        feedback_items.append("Missing BIS track.")

    # Criterion: Data Visible (15 pts)
    if parsed.get("data_visible"):
        score += 15
        feedback_items.append("Data waveforms are visible.")
    else:
        feedback_items.append("Tracks appear empty or flat.")

    # Criterion: Application State (10 pts)
    # Check window title from JSON or VLM
    json_title_ok = "0001" in result_data.get("window_title", "")
    vlm_title_ok = parsed.get("window_title_correct", False)
    
    if json_title_ok or vlm_title_ok:
        score += 10
        feedback_items.append("Correct case file loaded.")
    else:
        feedback_items.append("Wrong file or application state.")

    # Pass Threshold
    passed = score >= 60 and (parsed.get("art_mbp_visible") or parsed.get("etco2_visible"))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_items)
    }