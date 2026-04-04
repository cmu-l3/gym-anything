#!/usr/bin/env python3
"""
Verifier for insert_revenue_chart task.

Combines programmatic file analysis (performed inside container) with
VLM visual verification of the trajectory.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying a task where a user must insert a column chart into a presentation slide.
Review the provided screenshots, which show the user's workflow.

Check for the following:
1. CHART_CREATION: Do you see the user inserting a chart? (e.g., "Insert Chart" dialog, default chart appearing)
2. DATA_ENTRY: Do you see a data table window where numbers are being entered? (Look for values like 2.4, 3.1, 2.8, 3.6)
3. CHART_VISIBLE: In the final frames, is there a bar/column chart visible on the slide?
4. SLIDE_CONTEXT: Does the slide look like a "Revenue Overview" slide (title visible)?

Respond in JSON format:
{
    "chart_creation_attempted": true/false,
    "data_entry_visible": true/false,
    "chart_visible_in_final": true/false,
    "chart_is_column_type": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_insert_revenue_chart(traj, env_info, task_info):
    """
    Verify the insertion of the revenue chart.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve programmatic results from container
    # The container script has already used python-pptx/odfpy to analyze the file
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            file_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        file_result = {"error": str(e)}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # --- Scoring ---

    # 1. File modification (Anti-gaming) - 15 pts
    if file_result.get("file_found") and file_result.get("modified_after_start"):
        score += 15
        feedback_parts.append("✅ File saved and modified")
    else:
        feedback_parts.append("❌ File not saved or not modified")

    # 2. Slide Count (Integrity) - 15 pts
    slide_count = file_result.get("slide_count", 0)
    if slide_count == 4:
        score += 15
        feedback_parts.append("✅ Slide count preserved (4)")
    else:
        feedback_parts.append(f"❌ Slide count changed (expected 4, got {slide_count})")

    # 3. Chart Presence on Slide 2 - 35 pts
    if file_result.get("chart_found_slide2"):
        score += 35
        feedback_parts.append("✅ Chart detected on Slide 2")
    else:
        feedback_parts.append("❌ No chart detected on Slide 2")

    # 4. Chart Type - 15 pts
    if file_result.get("chart_type_column"):
        score += 15
        feedback_parts.append("✅ Chart type appears to be Column/Bar")
    else:
        feedback_parts.append("⚠️ Chart type verification inconclusive or incorrect")

    # 5. Text Preservation - 20 pts
    if file_result.get("text_preserved"):
        score += 20
        feedback_parts.append("✅ Slide content preserved")
    else:
        feedback_parts.append("❌ Original slide text was modified/deleted")

    # --- VLM Verification (Backup/Confirmation) ---
    # Only use if programmatic check failed to find chart (ODP parsing can be tricky)
    # or to verify data entry (which programmatic script didn't check deeply)
    
    # We always run VLM for robust signal, but weight it based on programmatic result
    frames = sample_trajectory_frames(traj, n=4)
    vlm_res = None
    try:
        vlm_out = query_vlm(prompt=VLM_PROMPT, images=frames)
        if vlm_out.get("success"):
            vlm_res = vlm_out.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM query failed: {e}")

    # Bonus/Correction logic
    if vlm_res:
        if vlm_res.get("chart_visible_in_final") and not file_result.get("chart_found_slide2"):
            # Programmatic failed but VLM sees it (maybe saved in weird format)
            score += 25
            feedback_parts.append("⚠️ VLM detected chart (programmatic check failed)")
        
        if vlm_res.get("data_entry_visible"):
            # Bonus points for showing work
            if score < 100:
                score = min(100, score + 5)

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }