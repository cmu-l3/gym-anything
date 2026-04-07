#!/usr/bin/env python3
"""
Verifier for configure_wb_profile task.
Uses VLM to inspect the Avare Weight & Balance screen.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# VLM utilities provided by the framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Mock for local testing if needed
    def query_vlm(**kwargs): return {"success": False, "error": "ImportError"}
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying an aviation Weight & Balance task in the Avare app.
The user was asked to configure a specific aircraft profile.

Please analyze the screenshot and check for the following SPECIFIC values in the table:

1. **Station Names**: Look for "Front" (or Front Seat), "Rear" (or Rear Seat), "Fuel", and "Baggage".
2. **Arms**:
   - Front Arm: 37
   - Rear Arm: 73
   - Fuel Arm: 48
   - Baggage Arm: 95
3. **Weights**:
   - Front Weight: 350
   - Rear Weight: 150
   - Fuel Weight: 180
   - Baggage Weight: 50
4. **Calculations**:
   - Is a Total Weight visible? It should be around 2330 (1600 empty + 730 load).
   - Is a Center of Gravity (CG) value calculated/displayed?

Output JSON with these boolean fields:
{
    "screen_is_wb_tool": true/false,
    "stations_defined": true/false,
    "arms_correct": true/false,
    "weights_entered": true/false,
    "total_weight_correct": true/false,
    "cg_calculated": true/false,
    "visible_values": {
       "total_weight": "number found or null",
       "found_arms": ["list of arms found"],
       "found_weights": ["list of weights found"]
    }
}
"""

def verify_wb_profile(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that the Weight & Balance profile was configured correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    
    # 1. Retrieve Metadata & Timestamp Check
    metadata_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        if copy_from_env:
            copy_from_env("/sdcard/task_metadata.json", metadata_file.name)
            with open(metadata_file.name, 'r') as f:
                meta = json.load(f)
        else:
            meta = {}
    except Exception as e:
        logger.warning(f"Could not read metadata: {e}")
        meta = {}
    finally:
        if os.path.exists(metadata_file.name):
            os.unlink(metadata_file.name)

    app_running = meta.get("app_running", False)
    
    # 2. VLM Verification (Primary)
    final_screenshot = get_final_screenshot(traj)
    if not final_screenshot:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No screenshot available for verification."
        }

    vlm_result = query_vlm(
        prompt=VLM_PROMPT,
        image=final_screenshot
    )

    if not vlm_result.get("success"):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"VLM analysis failed: {vlm_result.get('error')}"
        }

    data = vlm_result.get("parsed", {})
    logger.info(f"VLM Result: {json.dumps(data, indent=2)}")

    # 3. Scoring
    score = 0
    feedback_parts = []

    # Criterion 1: App running and on correct screen (20 pts)
    if app_running and data.get("screen_is_wb_tool"):
        score += 20
        feedback_parts.append("W&B Tool accessed.")
    elif not data.get("screen_is_wb_tool"):
        feedback_parts.append("Screen does not appear to be the Weight & Balance tool.")

    # Criterion 2: Stations Defined (10 pts)
    if data.get("stations_defined"):
        score += 10
        feedback_parts.append("Stations defined.")
    else:
        feedback_parts.append("Missing required stations (Front, Rear, Fuel, Baggage).")

    # Criterion 3: Arms Correct (20 pts)
    if data.get("arms_correct"):
        score += 20
        feedback_parts.append("Arms set correctly.")
    else:
        feedback_parts.append("Incorrect Arms (expected 37, 73, 48, 95).")

    # Criterion 4: Weights Correct (30 pts)
    if data.get("weights_entered"):
        score += 30
        feedback_parts.append("Load weights entered correctly.")
    else:
        feedback_parts.append("Incorrect Weights (expected 350, 150, 180, 50).")

    # Criterion 5: Calculation Valid (20 pts)
    if data.get("total_weight_correct") or data.get("cg_calculated"):
        score += 20
        feedback_parts.append("Calculations displayed.")
    else:
        feedback_parts.append("Total Weight/CG not calculated.")

    passed = score >= 80  # Requires most components to be correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": data
    }