#!/usr/bin/env python3
"""
Verifier for create_scatter_trend task in Oracle Analytics Desktop.

Verification Strategy:
1. File Verification (25 pts): Check if 'shipping_analysis.dva' exists and was modified.
2. VLM Trajectory Verification (75 pts):
   - Verify workflow progression (Canvas creation, chart selection).
   - Verify final chart content:
     - Scatter plot geometry (dots).
     - Axes labels (Revenue vs Shipping Cost).
     - Color legend (Product Category).
     - Trend line visible.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utils from the framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "ImportError"}
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_SCATTER_PROMPT = """You are evaluating an agent's work in Oracle Analytics Desktop.
The task was to create a Scatter Plot visualizing 'Revenue' vs 'Shipping Cost', colored by 'Product Category', with a Trend Line.

Analyze the provided screenshots (trajectory and final state).

Check for these specific elements:
1. **Chart Type**: Is there a scatter plot (a cloud of points, not bars or lines)?
2. **Axes**: Can you see "Revenue" and "Shipping Cost" labels on the axes?
3. **Color**: Are the points colored by "Product Category" (look for a legend or multi-colored dots)?
4. **Trend Line**: Is there a straight line passing through the points (correlation/regression line)?
5. **Canvas Name**: Is the tab/canvas named "Shipping Analysis"?

Respond in JSON format:
{
    "scatter_plot_visible": true/false,
    "axes_correct": true/false,
    "color_applied": true/false,
    "trend_line_visible": true/false,
    "canvas_renamed": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what you see"
}
"""

def verify_create_scatter_trend(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the scatter plot task using file checks and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    # =========================================================
    # 1. FILE VERIFICATION (25 Points)
    # =========================================================
    file_score = 0
    feedback_parts = []
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Copy result from Windows path to temp local file
        # Note: The path in copy_from_env usually maps to the container's path.
        # If the environment exposes C:\tmp via a mount or specific path, we use that.
        # Assuming the standard convention for this env:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
            
        if result.get('output_exists'):
            file_score += 10
            feedback_parts.append("Workbook file saved.")
            
            if result.get('file_created_during_task'):
                file_score += 15
                feedback_parts.append("Workbook modified during task.")
            else:
                feedback_parts.append("Workbook not modified during task.")
        else:
            feedback_parts.append("Workbook file not found.")
            
    except Exception as e:
        logger.error(f"Failed to read file result: {e}")
        feedback_parts.append("Failed to verify file output.")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # =========================================================
    # 2. VLM VERIFICATION (75 Points)
    # =========================================================
    vlm_score = 0
    
    # Get frames: trajectory samples + final state
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if final_frame:
        frames.append(final_frame)
        
    if not frames:
        return {
            "passed": False,
            "score": file_score,
            "feedback": "No screenshots available for VLM verification. " + " ".join(feedback_parts)
        }

    # Query VLM
    vlm_response = query_vlm(
        images=frames,
        prompt=VLM_SCATTER_PROMPT
    )
    
    if vlm_response.get("success"):
        parsed = vlm_response.get("parsed", {})
        
        # Scoring Criteria
        if parsed.get("scatter_plot_visible"):
            vlm_score += 25
            feedback_parts.append("Scatter plot verified.")
        else:
            feedback_parts.append("Scatter plot NOT detected.")
            
        if parsed.get("axes_correct"):
            vlm_score += 15
            feedback_parts.append("Axes labels verified.")
            
        if parsed.get("color_applied"):
            vlm_score += 15
            feedback_parts.append("Color category verified.")
            
        if parsed.get("trend_line_visible"):
            vlm_score += 10
            feedback_parts.append("Trend line verified.")
            
        if parsed.get("canvas_renamed"):
            vlm_score += 10
            feedback_parts.append("Canvas name verified.")
            
    else:
        feedback_parts.append(f"VLM verification failed: {vlm_response.get('error')}")

    # =========================================================
    # FINAL SCORE
    # =========================================================
    total_score = file_score + vlm_score
    passed = total_score >= 60 and parsed.get("scatter_plot_visible", False)
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file_score": file_score,
            "vlm_score": vlm_score,
            "vlm_reasoning": parsed.get("reasoning", "") if vlm_response.get("success") else ""
        }
    }