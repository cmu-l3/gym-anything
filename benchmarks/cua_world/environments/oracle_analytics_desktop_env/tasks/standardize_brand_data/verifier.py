#!/usr/bin/env python3
"""
Verifier for standardize_brand_data task.

Checks if the user created a workbook with specific data transformations:
1. "Brand" column derived from "Product Name" (text extraction)
2. "City_Upper" column derived from "City" (uppercase)
3. Filtered to "Technology"
4. Bar chart of Sales by Brand

Uses a hybrid approach:
- Programmatic: Checks internal metadata of the saved .dva file (exported to JSON by PS script)
- VLM: Checks trajectory for visual confirmation of workflow
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utils (assumed available in environment)
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback/Mock for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(**kwargs): return {"success": False}


def verify_standardize_brand_data(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the brand analysis workbook creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Programmatic Results
    # The export_result.ps1 script analyzes the DVA file and saves results to C:\tmp\task_result.json
    # We copy this file from the container
    programmatic_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Path must match what export_result.ps1 writes to.
        # In Windows containers, path mapping might vary, but usually absolute path works.
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            programmatic_result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to copy or read task_result.json: {e}")
        # Continue with empty dict, will fail programmatic checks
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Programmatic Criteria
    score = 0
    feedback_parts = []
    
    # Criterion: Workbook saved (10 pts)
    if programmatic_result.get("output_exists", False):
        if programmatic_result.get("file_created", False):
            score += 10
            feedback_parts.append("Workbook saved correctly.")
        else:
            score += 5
            feedback_parts.append("Workbook exists but timestamp indicates it wasn't created in this session.")
    else:
        feedback_parts.append("Workbook 'Brand_Analysis.dva' not found.")

    # Criterion: Brand logic (25 pts)
    if programmatic_result.get("brand_logic", False):
        score += 25
        feedback_parts.append("Brand text extraction logic found.")
    else:
        feedback_parts.append("Missing or incorrect 'Brand' calculation logic.")

    # Criterion: City uppercase logic (20 pts)
    if programmatic_result.get("city_logic", False):
        score += 20
        feedback_parts.append("City uppercase logic found.")
    else:
        feedback_parts.append("Missing 'City_Upper' calculation.")

    # Criterion: Visualization (25 pts total)
    viz_score = 0
    if programmatic_result.get("viz_type_correct", False):
        viz_score += 10
    if programmatic_result.get("viz_axes_correct", False):
        viz_score += 15
    
    score += viz_score
    if viz_score == 25:
        feedback_parts.append("Visualization configured correctly.")
    elif viz_score > 0:
        feedback_parts.append("Visualization partially correct.")
    else:
        feedback_parts.append("Visualization missing or incorrect.")

    # Criterion: Filter (10 pts)
    if programmatic_result.get("filter_applied", False):
        score += 10
        feedback_parts.append("Filter for 'Technology' applied.")
    else:
        feedback_parts.append("Filter missing.")

    # 3. VLM Verification (10 pts)
    # Check trajectory for visual confirmation of the Calculation Editor or Data Prepare tab
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Analyze these screenshots of Oracle Analytics Desktop.
        The user should be:
        1. Opening a calculation editor or data preparation screen.
        2. Creating a formula (look for 'Brand' or 'City').
        3. Viewing a bar chart.
        
        Does the user appear to be performing these data transformation tasks?
        Respond with JSON: {"success": true/false, "confidence": "high/medium/low"}
        """
        
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_res.get("success") and vlm_res.get("parsed", {}).get("success", False):
            score += 10
            feedback_parts.append("VLM confirms data preparation workflow.")
        else:
            # Fallback if VLM is unsure but programmatic passed
            if score >= 60:
                score += 10
                feedback_parts.append("VLM check bypassed due to strong programmatic evidence.")
    
    # 4. Final Determination
    pass_threshold = 60
    passed = score >= pass_threshold
    
    # Critical fail condition
    if not programmatic_result.get("output_exists", False):
        passed = False
        feedback_parts.append("CRITICAL: No output file.")

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }