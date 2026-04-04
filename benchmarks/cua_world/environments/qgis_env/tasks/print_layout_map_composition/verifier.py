#!/usr/bin/env python3
"""
Verifier for print_layout_map_composition task.

Verifies:
1. QGIS project creation (validity, layers)
2. Print Layout composition (presence of Map, Title, Legend, ScaleBar)
3. Export success (PNG file existence and size)
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_print_layout_map_composition(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the QGIS print layout task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 1. Retrieve result from environment
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                task_result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

    analysis = task_result.get("analysis", {})
    logger.info(f"Analysis result: {analysis}")

    score = 0
    max_score = 100
    feedback = []
    
    # ---------------------------------------------------------
    # Criterion 1: Project File (20 points)
    # ---------------------------------------------------------
    if analysis.get("project_found"):
        if analysis.get("valid_xml"):
            score += 20
            feedback.append("Valid QGIS project file found (+20)")
        else:
            score += 10
            feedback.append("Project file found but invalid XML (+10)")
    else:
        feedback.append("No QGIS project file found (0)")

    # ---------------------------------------------------------
    # Criterion 2: Layers Loaded (20 points)
    # ---------------------------------------------------------
    layer_count = analysis.get("layer_count", 0)
    if layer_count >= 2:
        score += 20
        feedback.append(f"Correct number of layers loaded ({layer_count}) (+20)")
    elif layer_count == 1:
        score += 10
        feedback.append("Only 1 layer loaded, expected 2+ (+10)")
    else:
        feedback.append("No layers found in project (0)")

    # ---------------------------------------------------------
    # Criterion 3: Layout & Items (40 points)
    # ---------------------------------------------------------
    if analysis.get("layout_found"):
        score += 10
        feedback.append("Print Layout created (+10)")
        
        items = analysis.get("layout_items", [])
        
        # Map Item
        if "Map" in items:
            score += 10
            feedback.append("Map item present (+10)")
        else:
            feedback.append("Missing Map item")
            
        # Legend Item
        if "Legend" in items:
            score += 10
            feedback.append("Legend item present (+10)")
        else:
            feedback.append("Missing Legend item")
            
        # Label/Title & ScaleBar (combined 10 pts)
        extras = 0
        if "Label" in items: extras += 5
        if "ScaleBar" in items: extras += 5
        score += extras
        if extras > 0:
            feedback.append(f"Title/ScaleBar present (+{extras})")
    else:
        feedback.append("No Print Layout found (0)")

    # ---------------------------------------------------------
    # Criterion 4: Export (20 points)
    # ---------------------------------------------------------
    if analysis.get("export_found"):
        size_kb = analysis.get("export_size_kb", 0)
        if size_kb > 50:
            score += 20
            feedback.append(f"Valid export found ({int(size_kb)} KB) (+20)")
        elif size_kb > 0:
            score += 10
            feedback.append("Export found but file size suspiciously small (+10)")
    else:
        feedback.append("No exported map image found (0)")

    # ---------------------------------------------------------
    # VLM Verification (Bonus/Confirmation)
    # ---------------------------------------------------------
    # If using gym_anything.vlm, we could verify the visual content here.
    # Since we have strong programmatic verification of the XML, 
    # we treat this as supplementary for now.
    
    passed = score >= 55
    final_feedback = " | ".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }