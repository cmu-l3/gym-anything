#!/usr/bin/env python3
"""
Verifier for create_bubble_portfolio task in Oracle Analytics Desktop.

Verifies:
1. Workbook creation and saving (.dva file existence and timestamp)
2. File structure (DVA/ZIP inspection for canvas names)
3. Visual validation via VLM (Chart type, Axis labels, Color/Size encodings)
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

# Adjust import based on environment structure (assuming gym_anything.vlm exists)
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Mock for testing
    def query_vlm(**kwargs): return {"success": False, "error": "ImportError"}
    def get_final_screenshot(t): return None
    def sample_trajectory_frames(t, n): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_bubble_portfolio(traj, env_info, task_info):
    """
    Verify the product portfolio bubble chart task.
    
    Strategy:
    - Primary: VLM Trajectory & Final Screenshot Analysis (Did they build the chart?)
    - Secondary: File system check (Did they save the workbook?)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    
    # --- Step 1: Retrieve Exported JSON from Container ---
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: copy_from_env must handle Windows paths if the env is Windows
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Step 2: File-Based Verification (40 points) ---
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    canvas_found = result.get('internal_canvas_found', False)
    title_found = result.get('internal_title_found', False)
    
    if output_exists:
        score += 10
        feedback.append("Workbook file saved.")
        if created_during:
            score += 10
            feedback.append("Workbook created during task session.")
        else:
            feedback.append("Warning: Workbook timestamp predates task.")
            
        if canvas_found:
            score += 10
            feedback.append("Internal XML confirms canvas 'Portfolio Analysis'.")
        if title_found:
            score += 10
            feedback.append("Internal XML confirms chart title.")
    else:
        feedback.append("Workbook 'portfolio_analysis.dva' not found.")

    # --- Step 3: VLM Visual Verification (60 points) ---
    # We use trajectory frames to ensure they didn't just load a pre-made file immediately
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if not final_shot:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback) + " (No screenshot)"}
        
    all_images = frames + [final_shot]
    
    prompt = """
    You are verifying an Oracle Analytics Desktop task.
    The user should have created a 'Bubble Chart' (Scatter Plot).
    
    Look at the image sequence. 
    1. Is there a Scatter/Bubble chart visible in the final state? (Look for dots/bubbles on an X-Y plane).
    2. Are there multiple colored bubbles of DIFFERENT SIZES? (This confirms Size and Color encoding).
    3. Do the axes look like 'Sales' (X) and 'Profit' (Y)?
    4. Is the visualization title 'Product Sub-Category Portfolio Analysis'?
    5. Is the canvas tab named 'Portfolio Analysis'?
    
    Respond in JSON:
    {
        "chart_type_correct": boolean,
        "bubbles_have_different_sizes": boolean,
        "bubbles_have_colors": boolean,
        "axes_correct": boolean,
        "title_correct": boolean,
        "canvas_name_correct": boolean,
        "confidence": "low|medium|high"
    }
    """
    
    vlm_resp = query_vlm(images=all_images, prompt=prompt)
    
    if vlm_resp.get("success"):
        analysis = vlm_resp.get("parsed", {})
        
        if analysis.get("chart_type_correct"):
            score += 15
            feedback.append("VLM: Scatter/Bubble chart detected.")
        else:
            feedback.append("VLM: Chart type looks incorrect.")
            
        if analysis.get("bubbles_have_different_sizes"):
            score += 10
            feedback.append("VLM: Bubble sizes vary (Quantity mapped).")
            
        if analysis.get("bubbles_have_colors"):
            score += 10
            feedback.append("VLM: Bubbles are colored (Category mapped).")
            
        if analysis.get("axes_correct"):
            score += 10
            feedback.append("VLM: Axes labels appear correct (Sales/Profit).")
            
        if analysis.get("title_correct") or title_found:
            score += 10
            feedback.append("VLM: Title verified.")
            
        if analysis.get("canvas_name_correct") or canvas_found:
            score += 5
            feedback.append("VLM: Canvas name verified.")
    else:
        feedback.append("VLM verification failed to run.")

    # --- Final Decision ---
    # Pass if file saved AND visual check confirms core chart properties
    passed = (score >= 60) and output_exists and vlm_resp.get("success", False)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }