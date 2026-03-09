#!/usr/bin/env python3
"""
Verifier for check_combo_therapy_beta_blocker_safety task.

Logic:
1. Verify report file exists and was created during the task.
2. Parse report for Vemurafenib and Cobimetinib interaction colors.
3. Verify "Worst-case" logic (Red > Orange > Yellow > Green > Grey).
4. VLM: Verify trajectory shows navigation to BOTH drugs.
"""

import json
import re
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SEVERITY_MAP = {
    "red": 5,
    "orange": 4,
    "yellow": 3,
    "green": 2,
    "grey": 1,
    "gray": 1,
    "not found": 0
}

def parse_report_content(content):
    """
    Parses the agent's text report.
    Expected format:
    Vemurafenib + Metoprolol: [COLOR]
    Cobimetinib + Metoprolol: [COLOR]
    Worst-case interaction: [COLOR]
    """
    normalized = content.lower()
    
    # Extract colors using regex
    vem_match = re.search(r"vemurafenib.*?metoprolol.*?:.*?(\w+)", normalized)
    cob_match = re.search(r"cobimetinib.*?metoprolol.*?:.*?(\w+)", normalized)
    worst_match = re.search(r"worst.*?case.*?:.*?(\w+)", normalized)
    
    return {
        "vemurafenib_color": vem_match.group(1) if vem_match else None,
        "cobimetinib_color": cob_match.group(1) if cob_match else None,
        "worst_case_color": worst_match.group(1) if worst_match else None
    }

def verify_combo_therapy_safety(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # =========================================================
    # 1. Retrieve Result JSON
    # =========================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # =========================================================
    # 2. Programmatic Checks (File & Content) - 60 Points
    # =========================================================
    
    # Check 1: File Existence (15 pts)
    if result_data.get("report_exists"):
        score += 15
        feedback_parts.append("Report file exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not found"}

    # Check 2: Anti-Gaming Timestamp (5 pts)
    if result_data.get("file_created_during_task"):
        score += 5
    else:
        feedback_parts.append("Warning: Report file not created during task (stale?)")

    # Check 3: Content Parsing & Validity (20 pts)
    content = result_data.get("report_content", "")
    parsed = parse_report_content(content)
    
    vem_color = parsed.get("vemurafenib_color")
    cob_color = parsed.get("cobimetinib_color")
    reported_worst = parsed.get("worst_case_color")
    
    valid_colors = SEVERITY_MAP.keys()
    
    if vem_color in valid_colors:
        score += 10
        feedback_parts.append(f"Vemurafenib result: {vem_color}")
    else:
        feedback_parts.append(f"Invalid/Missing Vemurafenib color: {vem_color}")

    if cob_color in valid_colors:
        score += 10
        feedback_parts.append(f"Cobimetinib result: {cob_color}")
    else:
        feedback_parts.append(f"Invalid/Missing Cobimetinib color: {cob_color}")

    # Check 4: Logic Consistency (20 pts)
    # The agent calculates worst case. We verify their math, not the medical truth (to allow for app updates)
    if vem_color in valid_colors and cob_color in valid_colors and reported_worst in valid_colors:
        vem_score = SEVERITY_MAP.get(vem_color, 0)
        cob_score = SEVERITY_MAP.get(cob_color, 0)
        expected_worst_score = max(vem_score, cob_score)
        reported_worst_score = SEVERITY_MAP.get(reported_worst, 0)
        
        if reported_worst_score == expected_worst_score:
            score += 20
            feedback_parts.append("Worst-case logic is correct")
        else:
            feedback_parts.append(f"Worst-case logic mismatch: expected level {expected_worst_score}, got {reported_worst_score}")
    else:
        feedback_parts.append("Cannot verify logic due to invalid color inputs")

    # =========================================================
    # 3. VLM Verification (Trajectory) - 40 Points
    # =========================================================
    
    # We need to ensure the agent actually looked up BOTH drugs.
    # A single screenshot isn't enough; we need the history.
    
    frames = sample_trajectory_frames(traj, n=8)  # Sample 8 frames
    
    prompt = """
    You are verifying an agent using the 'Liverpool Cancer iChart' app.
    The task requires checking two specific cancer drugs:
    1. Vemurafenib
    2. Cobimetinib
    
    Look at this sequence of screenshots.
    
    Q1: Do you see the agent searching for or viewing 'Vemurafenib'?
    Q2: Do you see the agent searching for or viewing 'Cobimetinib'?
    Q3: Do you see 'Beta Blockers' or 'Metoprolol' being selected or viewed?
    Q4: Do you see any traffic light color results (Red, Orange, Yellow, Green)?
    
    Return JSON:
    {
        "saw_vemurafenib": true/false,
        "saw_cobimetinib": true/false,
        "saw_metoprolol_or_beta": true/false,
        "saw_results": true/false
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    if vlm_result.get("success"):
        vlm_data = vlm_result.get("parsed", {})
        
        if vlm_data.get("saw_vemurafenib"):
            score += 10
            feedback_parts.append("VLM: Saw Vemurafenib lookup")
        
        if vlm_data.get("saw_cobimetinib"):
            score += 10
            feedback_parts.append("VLM: Saw Cobimetinib lookup")
            
        if vlm_data.get("saw_metoprolol_or_beta"):
            score += 10
            feedback_parts.append("VLM: Saw Beta Blocker lookup")
            
        if vlm_data.get("saw_results"):
            score += 10
            feedback_parts.append("VLM: Saw result screens")
    else:
        feedback_parts.append("VLM verification failed to run")

    # Final Score Calculation
    passed = score >= 55 and result_data.get("report_exists") and result_data.get("file_created_during_task")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }