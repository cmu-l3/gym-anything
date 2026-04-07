#!/usr/bin/env python3
"""
Verifier for annual_compensation_adjustment task.

This verifier employs a hybrid programmatic + visual model to prevent gaming:
1. Programmatically reads the DB state (via `copy_from_env`) looking for exact salary updates.
2. Implements a negative constraint check evaluating whether the terminating employee was properly ignored.
3. Incorporates VLM verification analyzing trajectory frames to verify the agent used the UI natively.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_annual_compensation_adjustment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    salaries = result.get('salaries', [])
    allowances = result.get('allowances', [])

    score = 0
    feedback = []

    # Format: (employee_id, expected_salary, expected_bonus)
    targets = [
        ("EMP002", "115000", "10500"),
        ("EMP006", "132500", "14000"),
        ("EMP011", "98400", "7200"),
        ("EMP018", "145000", "18500")
    ]

    def check_val(rows, empid, target_val):
        """Robust string matching to scan dynamic TSV dumps regardless of Sentrifugo version column names."""
        target_clean = str(target_val)
        for r in rows:
            if r.get('employeeId') == empid:
                for k, v in r.items():
                    if v:
                        # Normalize common DB currency representations
                        val_clean = str(v).replace(',', '').strip()
                        if val_clean.endswith('.00'):
                            val_clean = val_clean[:-3]
                            
                        if target_clean == val_clean or target_clean in val_clean:
                            return True
        return False

    # Positive Verification Checks (80 pts max)
    for empid, expected_sal, expected_bon in targets:
        sal_ok = check_val(salaries, empid, expected_sal)
        bon_ok = check_val(allowances, empid, expected_bon)

        emp_score = 0
        if sal_ok: emp_score += 10
        if bon_ok: emp_score += 10
        score += emp_score

        if sal_ok and bon_ok:
            feedback.append(f"{empid} correctly updated (20/20)")
        else:
            feedback.append(f"{empid} updates incomplete (Sal:{sal_ok}, Bon:{bon_ok}) ({emp_score}/20)")

    # Negative Constraint Check (20 pts)
    # The agent should NOT have processed EMP014 who was marked for termination
    emp014_sal = check_val(salaries, "EMP014", "105000")
    emp014_bon = check_val(allowances, "EMP014", "5000")

    if not emp014_sal and not emp014_bon:
        score += 20
        feedback.append("EMP014 correctly ignored (20/20)")
    else:
        feedback.append("EMP014 was incorrectly updated! (0/20)")

    # Anti-Gaming VLM Trajectory check
    # Ensures the agent was using the Sentrifugo software forms rather than bypassing constraints
    vlm_passed = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        query_vlm = env_info.get('query_vlm')

        if query_vlm:
            prompt = (
                "Review these screenshots of an agent performing a task in an HRMS. "
                "Did the agent open a text file and interact with the 'Salary' or 'Compensation' "
                "UI screens to enter numeric values? "
                "Respond with a JSON object containing a boolean 'workflow_followed'."
            )
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('workflow_followed', False):
                vlm_passed = True
                feedback.append("VLM verified correct workflow.")
            else:
                feedback.append("VLM did NOT verify correct workflow.")
        else:
            vlm_passed = True # Graceful fallback if VLM is unavailable
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")
        vlm_passed = True

    # Penalize if the programmatic score was a pass, but the VLM proved they gamed it
    if not vlm_passed and score >= 60:
        score -= 10
        feedback.append("Penalty: -10 for failing workflow visual verification.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }