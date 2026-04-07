#!/usr/bin/env python3
"""
Verifier for create_logistics_sankey task in Oracle Analytics Desktop.

Verification Strategy:
1. File-based (DVA export analysis):
   - Checks if .dva file exists and was created during task
   - Checks internal metadata for 'sankey' visualization type
   - Checks if correct dimensions (Priority, Ship Mode, Segment) are used
2. VLM-based (Trajectory & Final State):
   - Verifies the visual appearance of a Sankey diagram (ribbons/flows)
   - Checks for title "Order Priority Flow Analysis"
   - Confirm workflow progression
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for Visual Verification
VLM_PROMPT = """You are verifying an Oracle Analytics Desktop task.
The user was asked to create a SANKEY DIAGRAM showing the flow of orders.

Look at the provided screenshot(s) and determine:
1. Is a Sankey Diagram visible? (Look for flow ribbons connecting nodes, NOT simple bars or lines).
2. Are there multiple stages visible? (e.g., Left nodes -> Middle nodes -> Right nodes).
3. Do you see labels related to "Order Priority" (Critical, High, Low), "Ship Mode" (Regular Air, Express), or "Customer Segment"?
4. Is the title "Order Priority Flow Analysis" visible?

Return JSON:
{
  "is_sankey_visible": true/false,
  "flow_stages_visible": true/false,
  "correct_labels_visible": true/false,
  "title_correct": true/false,
  "confidence": "low/medium/high"
}
"""

def verify_logistics_sankey(traj, env_info, task_info):
    """
    Verify the creation of the Logistics Flow Sankey Chart.
    """
    # 1. Setup & Helper extraction
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm', None) # Might be provided by framework
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # 2. Retrieve Programmatic Results (exported by PowerShell script)
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: PowerShell script saved to C:\tmp\task_result.json
        # In Docker/Wine mapping, this is usually /tmp/task_result.json or similar.
        # Adjust path if env specific, but assuming standard linux-path mapping for copy_from_env
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task result file: {e}")
        # Continue, as VLM might still save the day, but with penalty
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Retrieve VLM Verification
    # Use the final screenshot from the trajectory
    vlm_score = 0
    vlm_feedback = []
    
    if query_vlm and traj:
        # Get final screenshot
        final_img = traj[-1].get('observation', {}).get('screenshot', None) if traj else None
        
        if final_img:
            try:
                vlm_resp = query_vlm(prompt=VLM_PROMPT, image=final_img)
                if vlm_resp and vlm_resp.get('success'):
                    parsed = vlm_resp.get('parsed', {})
                    if parsed.get('is_sankey_visible'):
                        vlm_score += 20
                        vlm_feedback.append("VLM confirms Sankey diagram visible")
                    if parsed.get('correct_labels_visible'):
                        vlm_score += 10
                        vlm_feedback.append("VLM sees correct data labels")
                    if parsed.get('title_correct'):
                        vlm_score += 10
                        vlm_feedback.append("VLM confirms correct title")
            except Exception as e:
                logger.error(f"VLM query failed: {e}")

    # 4. Scoring Logic
    score = 0
    feedback = []

    # Criterion A: File created (20 pts)
    if task_result.get('output_exists') and task_result.get('file_created_during_task'):
        score += 20
        feedback.append("Workbook file created successfully")
    elif task_result.get('output_exists'):
        score += 10
        feedback.append("Workbook file exists but timestamp unclear")
    else:
        feedback.append("Workbook file NOT found")

    # Criterion B: Internal Metadata Check (40 pts)
    # This is the strongest signal - proving they actually configured the tool
    if task_result.get('is_sankey_chart'):
        score += 20
        feedback.append("Internal metadata confirms Sankey chart type")
    
    if task_result.get('dimensions_mapped'):
        score += 20
        feedback.append("Internal metadata confirms correct dimensions mapped")
    elif task_result.get('measure_mapped'):
        score += 10 # Partial credit if dimensions missed but measure found
        feedback.append("Internal metadata confirms measure mapped")

    # Add VLM score (Max 40 pts)
    score += vlm_score
    feedback.extend(vlm_feedback)

    # Final Pass/Fail
    # Must have created file AND (Metadata confirmed Sankey OR VLM confirmed Sankey)
    has_sankey = task_result.get('is_sankey_chart') or (vlm_score >= 20)
    passed = (score >= 70) and has_sankey and task_result.get('output_exists')

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }