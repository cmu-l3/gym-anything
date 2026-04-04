#!/usr/bin/env python3
"""
Verifier for swot_analysis_template task.

Scoring System (100 points total):
- File Validation (20 pts): Valid flipchart file exists at correct path.
- Text Content (55 pts):
    - Title keyword "Device Program" or "SWOT" (15 pts)
    - "Strengths" (10 pts)
    - "Weaknesses" (10 pts)
    - "Opportunities" (10 pts)
    - "Threats" (10 pts)
- Grid Structure (25 pts):
    - Evidence of lines or shapes forming the matrix (Programmatic Check)
    - Visual layout verification via VLM (Secondary Check)

Pass Threshold: 75 points.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_swot_vlm_prompt():
    return """Examine this screenshot of a whiteboard flipchart.
    
Task: Verify if this is a SWOT analysis template.

Check for the following:
1. LAYOUT: Is there a 2x2 grid or matrix structure? (formed by lines or boxes).
2. LABELS: Do you see the words "Strengths", "Weaknesses", "Opportunities", and "Threats"?
3. ARRANGEMENT: Are these labels arranged in the four quadrants of the grid?
4. TITLE: Is there a title at the top referencing "Device Program" or "SWOT"?

Respond in JSON format:
{
    "is_2x2_grid": true/false,
    "labels_present": true/false,
    "labels_in_quadrants": true/false,
    "title_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""

def verify_swot_template(traj, env_info, task_info):
    """
    Verify the SWOT analysis template creation.
    Combines file-based content checks with VLM visual verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # 1. Load Programmatic Results
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Validation (20 pts) ---
    if result.get('file_found') and result.get('file_valid') and result.get('created_during_task'):
        score += 20
        feedback_parts.append("Valid flipchart created (20/20)")
    elif result.get('file_found'):
        score += 10
        feedback_parts.append("File found but issue with validity/timing (10/20)")
    else:
        feedback_parts.append("File not found (0/20)")
        return {"passed": False, "score": 0, "feedback": "File not found"}

    # --- Criterion 2: Text Content (55 pts) ---
    # Title (15 pts)
    if result.get('has_title_keyword'):
        score += 15
        feedback_parts.append("Title text found (15/15)")
    else:
        feedback_parts.append("Title missing (0/15)")

    # Labels (10 pts each)
    labels = [
        ('has_strengths', 'Strengths'),
        ('has_weaknesses', 'Weaknesses'),
        ('has_opportunities', 'Opportunities'),
        ('has_threats', 'Threats')
    ]
    
    for key, label in labels:
        if result.get(key):
            score += 10
            feedback_parts.append(f"'{label}' found")
        else:
            feedback_parts.append(f"'{label}' missing")

    # --- Criterion 3: Grid Structure (25 pts) ---
    # Programmatic check (15 pts)
    graphic_elements = result.get('total_graphic_elements', 0)
    programmatic_grid = False
    if graphic_elements >= 2: # At least 2 lines for a cross, or shapes
        score += 15
        programmatic_grid = True
        feedback_parts.append(f"Grid elements detected ({graphic_elements}) (15/15)")
    else:
        feedback_parts.append(f"No grid lines/shapes detected (0/15)")

    # VLM check (10 pts)
    vlm_score = 0
    if query_vlm:
        screenshot = get_final_screenshot(traj)
        if screenshot and os.path.exists(screenshot):
            vlm_response = query_vlm(
                prompt=build_swot_vlm_prompt(),
                image=screenshot
            )
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("is_2x2_grid") or parsed.get("labels_in_quadrants"):
                    vlm_score = 10
                    feedback_parts.append("VLM confirmed grid layout (10/10)")
                else:
                    feedback_parts.append("VLM did not verify grid layout")
            else:
                feedback_parts.append("VLM query failed")
        else:
            feedback_parts.append("No screenshot for VLM")
    
    score += vlm_score

    # Final Pass/Fail
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }