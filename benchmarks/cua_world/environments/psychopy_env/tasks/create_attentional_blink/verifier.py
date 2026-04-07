#!/usr/bin/env python3
"""
Verifier for create_attentional_blink task.

Criteria:
1. Experiment file exists, valid XML, modified during task (10 pts)
2. Conditions file exists, valid CSV, modified during task (10 pts)
3. CSV Content: 'lag' column with >=4 unique values (10 pts)
4. CSV Content: >=20 rows (5 pts)
5. XML Structure: Instructions routine (10 pts)
6. XML Structure: RSVP implementation (Text + Code component) (15 pts)
7. XML Structure: Response collection (Keyboard components for T1/T2) (10 pts)
8. XML Structure: Loop referencing conditions file (10 pts)
9. VLM: Visual workflow verification (20 pts)

Pass Threshold: 70/100
"""

import json
import tempfile
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_attentional_blink(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Import VLM utils if available
    from gym_anything.vlm import sample_trajectory_frames, query_vlm

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get JSON Result
    result = {}
    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

    # --- Verification Logic ---

    # 1. Experiment File (10 pts)
    if result.get("exp_exists") and result.get("exp_modified") and result.get("xml_valid"):
        score += 10
        feedback_parts.append("Experiment file created and valid.")
    else:
        feedback_parts.append("Experiment file missing, unmodified, or invalid XML.")

    # 2. Conditions File Existence (10 pts)
    if result.get("cond_exists") and result.get("cond_modified") and result.get("csv_valid"):
        score += 10
        feedback_parts.append("Conditions file created.")
    else:
        feedback_parts.append("Conditions file missing or invalid.")

    # 3. CSV Content: Lags (10 pts)
    unique_lags = result.get("unique_lags", [])
    if len(unique_lags) >= 4:
        score += 10
        feedback_parts.append(f"Sufficient lag diversity ({len(unique_lags)} unique lags).")
    else:
        feedback_parts.append(f"Insufficient lag diversity (found {len(unique_lags)}, need 4+).")

    # 4. CSV Content: Rows (5 pts)
    row_count = result.get("csv_row_count", 0)
    if row_count >= 20:
        score += 5
        feedback_parts.append(f"Sufficient trial count ({row_count}).")
    else:
        feedback_parts.append(f"Insufficient trial count ({row_count}, need 20+).")

    # 5. Instructions Routine (10 pts)
    # Check for a routine likely to be instructions (name contains 'instruct', 'intro', 'welcome')
    routines = [r.lower() for r in result.get("routines", [])]
    has_instructions = any(x in r for r in routines for x in ['instruct', 'intro', 'welcome', 'info'])
    if has_instructions:
        score += 10
        feedback_parts.append("Instructions routine detected.")
    else:
        feedback_parts.append("No obvious instructions routine found.")

    # 6. RSVP Implementation (15 pts)
    # Needs a Code component (for RSVP logic) AND a Text component (to display it)
    has_code = result.get("has_code_component", False)
    has_text = result.get("has_text", False)
    if has_code and has_text:
        score += 15
        feedback_parts.append("RSVP components (Code + Text) detected.")
    elif has_text:
        score += 5
        feedback_parts.append("Text component found, but missing Code component for RSVP logic.")
    else:
        feedback_parts.append("Missing components for RSVP stream.")

    # 7. Response Collection (10 pts)
    # Needs at least 2 keyboard components (T1 and T2) or distinct routines
    keyboards = [c for c in result.get("components", []) if 'Keyboard' in c.get('type', '')]
    if len(keyboards) >= 2:
        score += 10
        feedback_parts.append("Multiple keyboard responses detected (T1/T2).")
    elif len(keyboards) == 1:
        score += 5
        feedback_parts.append("Only one keyboard response found (need T1 and T2).")
    else:
        feedback_parts.append("No keyboard response components found.")

    # 8. Loops (10 pts)
    loops = result.get("loops", [])
    has_conditions_link = any("ab_conditions.csv" in l.get("conditionsFile", "") for l in loops)
    if loops and has_conditions_link:
        score += 10
        feedback_parts.append("Loop linked to conditions file detected.")
    elif loops:
        score += 5
        feedback_parts.append("Loop detected but conditions file link not verified.")
    else:
        feedback_parts.append("No loops detected.")

    # 9. VLM Verification (20 pts)
    # Use trajectory to verify the user actually interacted with the builder interface
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    You are verifying if a user created a PsychoPy experiment.
    Look at these screenshots of the process.
    
    1. Do you see the PsychoPy Builder interface (gray grid with routines like 'trial')?
    2. Is there evidence of a 'Code Component' or editing python code?
    3. Is there evidence of editing a conditions file (spreadsheet view)?
    
    Answer JSON: {"is_builder_visible": bool, "code_editing_visible": bool, "spreadsheet_visible": bool}
    """
    
    try:
        vlm_resp = query_vlm(images=frames, prompt=vlm_prompt).get("parsed", {})
        
        vlm_score = 0
        if vlm_resp.get("is_builder_visible"):
            vlm_score += 10
        if vlm_resp.get("code_editing_visible") or vlm_resp.get("spreadsheet_visible"):
            vlm_score += 10
            
        score += vlm_score
        if vlm_score > 0:
            feedback_parts.append(f"Visual verification passed ({vlm_score} pts).")
        else:
            feedback_parts.append("Visual verification failed (interface not recognized).")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if we have strong programmatic evidence, give partial points
        if score >= 50:
            score += 10
            feedback_parts.append("VLM failed, fallback points awarded based on file evidence.")

    # Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }