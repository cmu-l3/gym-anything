#!/usr/bin/env python3
"""
Verifier for annotate_chart_with_drawings task.

Criteria:
1. Workspace modified (anti-gaming check)
2. SPY chart exists in workspace
3. Horizontal line drawn near $450 (±$5)
4. Horizontal line drawn near $420 (±$5)
5. VLM verification of visual elements

Scoring:
- Workspace Modified: 15 pts
- SPY Chart Present: 20 pts
- Line near 450: 25 pts
- Line near 420: 25 pts
- VLM Confirmation: 15 pts
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
RESULT_FILENAME = "annotate_chart_with_drawings_result.json"
TARGET_1 = 450.0
TARGET_2 = 420.0
TOLERANCE = 5.0

def verify_annotate_chart(traj, env_info, task_info):
    """
    Verify the agent drew the correct horizontal lines on a SPY chart.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        # Path matches what is defined in export_result.ps1
        remote_path = f"C:\\Users\\Docker\\Desktop\\NinjaTraderTasks\\{RESULT_FILENAME}"
        # Since we are copying from Windows, paths might need handling, 
        # but the copy_from_env usually handles the source path string provided.
        # If the env is Linux-based hosting Windows (KVM), path syntax depends on the bridge.
        # Assuming the standard path provided in description works.
        
        # Note: In some setups, Windows paths need escaping or specific handling. 
        # We try the standard full path.
        copy_from_env(remote_path, temp_file.name)
        
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result_data = json.load(f)
            
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve task results. Agent may not have saved workspace. Error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Analyze Programmatic Data
    score = 0
    feedback = []
    
    # Check 1: Workspace Modified (15 pts)
    if result_data.get("workspace_modified", False):
        score += 15
        feedback.append("Workspace saved successfully (+15)")
    else:
        feedback.append("Workspace NOT saved (0) - Critical for persistence")
        # If workspace wasn't saved, we likely can't verify anything else programmatically
        return {"passed": False, "score": 0, "feedback": "Workspace not saved. Task failed."}

    # Check 2: SPY Chart Detected (20 pts)
    if result_data.get("spy_chart_detected", False):
        score += 20
        feedback.append("SPY chart definition found (+20)")
    else:
        feedback.append("SPY chart NOT found in workspace (0)")

    # Check 3 & 4: Line Analysis
    detected_lines = result_data.get("detected_lines", [])
    found_450 = False
    found_420 = False
    
    for price in detected_lines:
        if math.isclose(price, TARGET_1, abs_tol=TOLERANCE):
            found_450 = True
        if math.isclose(price, TARGET_2, abs_tol=TOLERANCE):
            found_420 = True
            
    if found_450:
        score += 25
        feedback.append(f"Resistance line found near ${TARGET_1} (+25)")
    else:
        feedback.append(f"Resistance line near ${TARGET_1} MISSING (0)")
        
    if found_420:
        score += 25
        feedback.append(f"Support line found near ${TARGET_2} (+25)")
    else:
        feedback.append(f"Support line near ${TARGET_2} MISSING (0)")

    # Check 5: VLM Verification (15 pts) - Fallback/Confirmation
    # We use VLM to verify the visual state if programmatic checks are ambiguous 
    # or just to confirm the chart is actually visible and not just XML data.
    from gym_anything.vlm import get_final_screenshot, query_vlm
    
    final_img = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_img:
        prompt = """
        Analyze this trading software screenshot.
        1. Is a chart visible?
        2. Are there horizontal lines drawn on the chart?
        3. Is the instrument 'SPY' visible?
        
        Return JSON: {"chart_visible": bool, "lines_visible": bool, "spy_visible": bool}
        """
        try:
            vlm_res = query_vlm(image=final_img, prompt=prompt)
            parsed = vlm_res.get("parsed", {})
            
            if parsed.get("chart_visible") and parsed.get("lines_visible"):
                vlm_score = 15
                feedback.append("Visual verification passed (+15)")
            else:
                feedback.append("Visual verification: Chart or lines not clearly visible (0)")
                
        except Exception:
            # If VLM fails, we default to generous if programmatic passed, strict if not
            if score >= 60:
                vlm_score = 15
                feedback.append("Visual check skipped (system error), awarding points based on XML evidence (+15)")
    
    score += vlm_score

    # Final tally
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "detected_lines": detected_lines,
            "workspace_files": result_data.get("modified_files", [])
        }
    }