#!/usr/bin/env python3
"""
Verifier for regulatory_pdf_markup task.
Analyzes the JSON result produced by export_result.sh and performs VLM verification.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_regulatory_pdf_markup(traj, env_info, task_info):
    """
    Verify PDF annotation task.
    
    Scoring Criteria:
    1. Output PDF exists and created during task (20 pts)
    2. Contains specific text "Verify tenure in HRIS" (30 pts)
    3. Contains Highlight annotation (25 pts)
    4. Contains Ink/Draw annotation (25 pts)
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 2. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion 1: File Existence (20 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 20
        feedback.append("Success: Annotated PDF saved.")
    elif result.get("file_exists"):
        score += 5
        feedback.append("Warning: File exists but timestamp predates task (did you save a new copy?).")
    else:
        feedback.append("Fail: Output PDF not found on Desktop.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Text Content (30 pts)
    if result.get("has_text_note") and result.get("has_target_text"):
        score += 30
        feedback.append("Success: Text note with correct content found.")
    elif result.get("has_target_text"):
        score += 25
        feedback.append("Success: Correct text found (annotation type uncertain).")
    else:
        feedback.append("Fail: 'Verify tenure in HRIS' text not found.")

    # Criterion 3: Highlight (25 pts)
    if result.get("has_highlight"):
        score += 25
        feedback.append("Success: Highlight annotation found.")
    else:
        feedback.append("Fail: No highlight annotation detected.")

    # Criterion 4: Ink/Draw (25 pts)
    if result.get("has_ink"):
        score += 25
        feedback.append("Success: Ink/Drawing annotation found.")
    else:
        feedback.append("Fail: No drawing/ink annotation detected.")

    # 4. Secondary VLM Check (Optional but good for robustness)
    # If score is marginal (e.g., failed to detect annotations via regex but file exists), 
    # use VLM to give partial credit for UI usage.
    if score < 70 and result.get("file_exists"):
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        prompt = "Do these screenshots show a user editing a PDF in a browser? Look for highlighter tools, adding text, or drawing."
        vlm_resp = query_vlm(frames, prompt)
        if vlm_resp.get("success") and "yes" in vlm_resp.get("response", "").lower():
            score = max(score, 60) # Bump to near-pass if visual evidence is strong
            feedback.append("(VLM confirmed PDF editing activity)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }