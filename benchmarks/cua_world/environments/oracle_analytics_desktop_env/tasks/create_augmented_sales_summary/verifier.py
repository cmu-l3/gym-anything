#!/usr/bin/env python3
"""
Verifier for create_augmented_sales_summary task.

Verification Strategy:
1. File-based: 
   - Check if 'Augmented_Summary.dva' exists and was created during the task.
   - Inspect internal DVA metadata (via export script) to confirm "bar" and "narrative" visualizations exist.
2. VLM-based (Hybrid):
   - Use trajectory frames to verify the agent created the specific visual layout.
   - Confirm a text summary block (Narrative) is visible alongside the chart.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for Visual Verification
VLM_PROMPT = """You are verifying an Oracle Analytics Desktop task.
The user was asked to create a dashboard with two specific components:
1. A Bar Chart showing Sales by Region.
2. A Language Narrative (a text block that automatically describes the data, e.g., "Sales for West is the highest...").

Look at the provided screenshot(s) and determine:
- Is there a Bar Chart visible?
- Is there a Text/Narrative block visible that describes data (not just a static title)?
- Do the text and chart appear to be on the same canvas?

Respond in JSON format:
{
    "bar_chart_visible": true/false,
    "narrative_text_visible": true/false,
    "layout_correct": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_augmented_sales_summary(traj, env_info, task_info):
    """
    Verify the Augmented Sales Summary task.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve programmatic results from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        # Note: The export script saves to C:\Temp\task_result.json, which maps to 
        # the container path. Adjust path if strictly Linux-based pathing is required by copy_from_env,
        # but typically for Windows envs, we use the absolute path or a mapped path.
        # Assuming standard copy_from_env handles the path provided by export script.
        # For Windows containers, paths might be tricky. Trying standard location.
        copy_from_env("C:\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy result file: {e}")
        # If copy fails, we rely heavily on VLM, but max score is limited
        result_data = {"output_exists": False}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Scoring (60 points max)
    score = 0
    feedback_parts = []
    
    # File existence (10 pts)
    if result_data.get("output_exists", False):
        score += 10
        feedback_parts.append("Workbook file created.")
    else:
        feedback_parts.append("Workbook file NOT found.")

    # Timestamp check (10 pts)
    if result_data.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task session.")
    elif result_data.get("output_exists", False):
        feedback_parts.append("File exists but timestamp check failed (stale file?).")

    # Internal Viz Check (40 pts)
    # These flags come from the export script analyzing the DVA xml content
    if result_data.get("viz_bar_found", False):
        score += 15
        feedback_parts.append("Bar chart metadata found.")
    
    if result_data.get("viz_narrative_found", False):
        score += 25
        feedback_parts.append("Narrative visualization metadata found.")
    else:
        feedback_parts.append("Narrative visualization NOT detected in file metadata.")

    # 3. VLM Verification (40 points max)
    # Import here to avoid global dependency issues
    try:
        from gym_anything.vlm import get_final_screenshot, query_vlm
        final_img = get_final_screenshot(traj)
        
        if final_img:
            vlm_response = query_vlm(
                prompt=VLM_PROMPT,
                image=final_img
            )
            
            if vlm_response and vlm_response.get("success"):
                vlm_parsed = vlm_response.get("parsed", {})
                
                if vlm_parsed.get("bar_chart_visible", False):
                    score += 15
                    feedback_parts.append("VLM confirmed Bar Chart visibility.")
                
                if vlm_parsed.get("narrative_text_visible", False):
                    score += 15
                    feedback_parts.append("VLM confirmed Narrative Text visibility.")
                
                if vlm_parsed.get("layout_correct", False):
                    score += 10
                    feedback_parts.append("VLM confirmed correct layout.")
            else:
                feedback_parts.append("VLM verification failed to process image.")
        else:
            feedback_parts.append("No screenshots available for VLM verification.")
            
    except ImportError:
        feedback_parts.append("VLM module not available.")
    except Exception as e:
        feedback_parts.append(f"VLM verification error: {str(e)}")

    # 4. Final Aggregation
    passed = score >= 70  # Threshold requiring substantial completion
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }