#!/usr/bin/env python3
"""
Verifier for create_multi_canvas_report task.

This task requires the agent to:
1. Create a workbook in Oracle Analytics Desktop.
2. Create and rename two specific canvases ("Revenue Overview", "Shipping Performance").
3. Build different visualizations on each (Bar Chart, Table).
4. Save the result.

Verification Strategy:
- Primary: VLM Trajectory Verification.
  - Checks if the agent actually interacted with the UI to rename tabs and build charts.
  - Verifies the final visual state contains two tabs with correct names.
  - Verifies the content of the charts.
- Secondary: File Verification.
  - Checks if 'Operational_Report.dva' exists and was modified during the task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_multi_canvas_report(traj, env_info, task_info):
    """
    Verify the multi-canvas report creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load File-based Results
    file_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Windows path in container is C:\tmp\task_result.json
        # copy_from_env should handle the path mapping or expect the internal path
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            file_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task result file: {e}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. VLM Verification
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    # Prompt for VLM to analyze the workflow and final state
    prompt = """
    You are evaluating an agent using Oracle Analytics Desktop.
    
    Task Requirements:
    1. Create a workbook with TWO canvases (tabs at the bottom).
    2. Rename Canvas 1 to "Revenue Overview".
    3. Rename Canvas 2 to "Shipping Performance".
    4. On "Revenue Overview", build a Stacked Bar Chart (Bars + Color).
    5. On "Shipping Performance", build a Table or Pivot Table.
    
    Review the screenshots provided (trajectory + final state) and answer:
    
    1. Are there TWO canvas tabs visible at the bottom of the screen in the final states?
    2. Is one tab named "Revenue Overview" (or similar)?
    3. Is one tab named "Shipping Performance" (or similar)?
    4. Does the "Revenue Overview" page show a Bar Chart?
    5. Does the "Shipping Performance" page show a Table/List?
    6. Did the agent navigate between screens/tabs during the session?
    
    Return JSON:
    {
        "two_canvases_exist": boolean,
        "canvas_revenue_named_correctly": boolean,
        "canvas_shipping_named_correctly": boolean,
        "bar_chart_created": boolean,
        "table_created": boolean,
        "workflow_observed": boolean,
        "confidence": "high/medium/low",
        "explanation": "brief reasoning"
    }
    """
    
    vlm_response = query_vlm(
        images=frames + [final_frame] if final_frame else frames,
        prompt=prompt
    )
    
    vlm_data = {}
    if vlm_response and vlm_response.get("success"):
        vlm_data = vlm_response.get("parsed", {})
    else:
        logger.error(f"VLM query failed: {vlm_response.get('error')}")

    # 3. Scoring
    score = 0
    feedback_parts = []
    
    # File Checks (30 points)
    if file_result.get("output_exists"):
        score += 15
        feedback_parts.append("Workbook file saved")
        if file_result.get("file_created_during_task"):
            score += 15
            feedback_parts.append("File created during session")
        else:
            feedback_parts.append("File timestamp check failed")
    else:
        feedback_parts.append("Workbook file NOT found")

    # VLM Checks (70 points)
    if vlm_data.get("two_canvases_exist"):
        score += 10
        feedback_parts.append("Two canvases detected")
    
    if vlm_data.get("canvas_revenue_named_correctly"):
        score += 15
        feedback_parts.append("'Revenue Overview' tab found")
    
    if vlm_data.get("canvas_shipping_named_correctly"):
        score += 15
        feedback_parts.append("'Shipping Performance' tab found")
        
    if vlm_data.get("bar_chart_created"):
        score += 10
        feedback_parts.append("Bar chart verified")
        
    if vlm_data.get("table_created"):
        score += 10
        feedback_parts.append("Table verified")
        
    if vlm_data.get("workflow_observed"):
        score += 10
        feedback_parts.append("Workflow progression observed")

    # Final Pass Determination
    # Must have saved file AND at least created/named the canvases correctly
    critical_vlm = (vlm_data.get("canvas_revenue_named_correctly") or vlm_data.get("canvas_shipping_named_correctly"))
    passed = (score >= 60) and file_result.get("output_exists") and critical_vlm

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file": file_result,
            "vlm": vlm_data
        }
    }