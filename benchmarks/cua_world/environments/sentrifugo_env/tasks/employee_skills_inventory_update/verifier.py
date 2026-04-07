#!/usr/bin/env python3
"""
Verifier for employee_skills_inventory_update task.
"""

import os
import json
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# The conditions define synonym groups. A row matches if AT LEAST ONE word from EACH group is found in the row.
EXPECTED_DATA = {
    'EMP002': {
        'education': [["mit", "massachusetts"], ["mechanical", "engineering"]],
        'experience': [["general electric", "ge"], ["project engineer"]],
        'skills': [["autocad"]]
    },
    'EMP008': {
        'education': [["georgia", "gatech"], ["electrical"]],
        'experience': [["siemens"], ["technician"]],
        'skills': [["scada"]]
    },
    'EMP011': {
        'education': [["pennsylvania", "upenn", "penn"], ["business", "mba"]],
        'experience': [["ibm"], ["product analyst"]],
        'skills': [["agile"]]
    }
}

def check_row_for_condition(row, conditions):
    """
    Checks if a row contains the required information.
    Concats all values in the TSV row into a single string to ignore schema/column names.
    `conditions` is a list of synonym lists.
    """
    full_text = " ".join(str(v).lower() for v in row.values() if v)
    
    for syn_group in conditions:
        if not any(syn.lower() in full_text for syn in syn_group):
            return False
    return True

def parse_tsv(filepath):
    """Reads a TSV file and returns a list of dictionary rows."""
    rows = []
    if os.path.exists(filepath):
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f, delimiter='\t')
            for row in reader:
                rows.append(row)
    return rows

def verify_skills_inventory(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # Temporary paths for copied files
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    tmp_ed = tempfile.NamedTemporaryFile(delete=False, suffix='.tsv').name
    tmp_ex = tempfile.NamedTemporaryFile(delete=False, suffix='.tsv').name
    tmp_sk = tempfile.NamedTemporaryFile(delete=False, suffix='.tsv').name
    tmp_initial = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name

    try:
        # Copy required files
        copy_from_env("/tmp/task_result.json", tmp_result)
        copy_from_env("/tmp/education.tsv", tmp_ed)
        copy_from_env("/tmp/experience.tsv", tmp_ex)
        copy_from_env("/tmp/skills.tsv", tmp_sk)
        copy_from_env("/tmp/initial_counts.json", tmp_initial)
        
        with open(tmp_result, 'r') as f:
            result = json.load(f)
        with open(tmp_initial, 'r') as f:
            initial_counts = json.load(f)

        ed_rows = parse_tsv(tmp_ed)
        ex_rows = parse_tsv(tmp_ex)
        sk_rows = parse_tsv(tmp_sk)

        # 1. Evaluate specific data entries (90 points total; 10 pts per correct entry)
        for empid, conditions in EXPECTED_DATA.items():
            # Check Education
            ed_matched = any(row.get('employeeId') == empid and check_row_for_condition(row, conditions['education']) for row in ed_rows)
            if ed_matched:
                score += 10
                feedback_parts.append(f"{empid} Education: Found")
            else:
                feedback_parts.append(f"{empid} Education: Missing")

            # Check Experience
            ex_matched = any(row.get('employeeId') == empid and check_row_for_condition(row, conditions['experience']) for row in ex_rows)
            if ex_matched:
                score += 10
                feedback_parts.append(f"{empid} Experience: Found")
            else:
                feedback_parts.append(f"{empid} Experience: Missing")

            # Check Skills
            sk_matched = any(row.get('employeeId') == empid and check_row_for_condition(row, conditions['skills']) for row in sk_rows)
            if sk_matched:
                score += 10
                feedback_parts.append(f"{empid} Skills: Found")
            else:
                feedback_parts.append(f"{empid} Skills: Missing")

        # 2. Precision/Anti-Gaming Check (10 points)
        # Check if the agent spam-added records across the whole database instead of just the target profiles
        final_counts = result.get('final_counts', {})
        added_ed = final_counts.get('education', 0) - initial_counts.get('education', 0)
        added_ex = final_counts.get('experience', 0) - initial_counts.get('experience', 0)
        added_sk = final_counts.get('skills', 0) - initial_counts.get('skills', 0)
        total_added = added_ed + added_ex + added_sk
        
        # We expect exactly 9 records added (3 ed + 3 ex + 3 sk). We allow a small margin for error (up to 12).
        if total_added <= 12:
            score += 10
            feedback_parts.append("Precision: Passed (no mass record spamming)")
        else:
            feedback_parts.append(f"Precision: Failed ({total_added} records added; expected 9)")

        # 3. VLM Verification (Bonus Trajectory Validation)
        vlm_check = False
        if "gym_anything.vlm" in sys.modules or hasattr(traj, "frames"):
            try:
                from gym_anything.vlm import sample_trajectory_frames, query_vlm
                frames = sample_trajectory_frames(traj, n=4)
                if frames:
                    prompt = "Did the agent use the Sentrifugo web interface to edit employee profiles? Look for screens showing employee details, education, experience, or skills tabs. Reply 'yes' or 'no'."
                    vlm_result = query_vlm(images=frames, prompt=prompt)
                    if vlm_result and "yes" in str(vlm_result).lower():
                        vlm_check = True
                        feedback_parts.append("VLM: Trajectory verified")
            except Exception as e:
                logger.warning(f"VLM verification failed to run: {e}")

        passed = score >= task_info.get("metadata", {}).get("pass_threshold", 70)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup temp files
        for f in [tmp_result, tmp_ed, tmp_ex, tmp_sk, tmp_initial]:
            if os.path.exists(f):
                os.unlink(f)