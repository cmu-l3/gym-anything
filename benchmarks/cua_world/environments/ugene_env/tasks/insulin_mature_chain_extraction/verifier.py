#!/usr/bin/env python3
"""
Verifier for insulin_mature_chain_extraction task.

Verification Strategy:
1. Programmatic validation of generated FASTA files (existence, length, exact sequence matches).
2. Header inspection to ensure files were exported natively from UGENE (anti-gaming).
3. Parsing the summary report for expected quantitative data.
4. Timestamps validation to ensure work was completed during the task window.
5. Trajectory VLM verification to confirm visual interaction with UGENE.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_insulin_mature_chain_extraction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_A_aa = metadata.get('target_A_aa', 'GIVEQCCTSICSLYQLENYCN')
    target_B_aa = metadata.get('target_B_aa', 'FVNQHLCGSHLVEALYLVCGERGFFYTPKT')
    len_A_nt = metadata.get('length_A_nt', 63)
    len_B_nt = metadata.get('length_B_nt', 90)

    score = 0
    feedback_parts = []
    
    # Extract results
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

    task_start = result.get('task_start', 0)
    
    # Helper to check if file was made during task
    def check_mtime(file_data):
        return file_data.get('mtime', 0) >= task_start

    A_nt = result.get("A_nt", {})
    A_aa = result.get("A_aa", {})
    B_nt = result.get("B_nt", {})
    B_aa = result.get("B_aa", {})

    # ================================================================
    # CRITERION 1: B Chain Nucleotide Export (15 pts)
    # ================================================================
    if B_nt.get("exists") and check_mtime(B_nt):
        if B_nt.get("length") == len_B_nt and bool(re.match(r'^[ACGTU]+$', B_nt.get("seq", ""))):
            score += 15
            feedback_parts.append(f"B Chain NT valid ({len_B_nt} bp)")
        else:
            score += 5
            feedback_parts.append(f"B Chain NT exists but invalid length/seq ({B_nt.get('length')} bp)")
    else:
        feedback_parts.append("B Chain NT missing or stale")

    # ================================================================
    # CRITERION 2: B Chain Amino Acid Export (20 pts)
    # ================================================================
    b_aa_match = False
    if B_aa.get("exists") and check_mtime(B_aa):
        if B_aa.get("seq") == target_B_aa:
            score += 20
            b_aa_match = True
            feedback_parts.append("B Chain AA exact match")
        elif target_B_aa in B_aa.get("seq", ""):
            score += 10
            feedback_parts.append("B Chain AA sequence partially matched/embedded")
        else:
            feedback_parts.append("B Chain AA sequence incorrect")
    else:
        feedback_parts.append("B Chain AA missing or stale")

    # ================================================================
    # CRITERION 3: A Chain Nucleotide Export (15 pts)
    # ================================================================
    if A_nt.get("exists") and check_mtime(A_nt):
        if A_nt.get("length") == len_A_nt and bool(re.match(r'^[ACGTU]+$', A_nt.get("seq", ""))):
            score += 15
            feedback_parts.append(f"A Chain NT valid ({len_A_nt} bp)")
        else:
            score += 5
            feedback_parts.append(f"A Chain NT exists but invalid length/seq ({A_nt.get('length')} bp)")
    else:
        feedback_parts.append("A Chain NT missing or stale")

    # ================================================================
    # CRITERION 4: A Chain Amino Acid Export (20 pts)
    # ================================================================
    a_aa_match = False
    if A_aa.get("exists") and check_mtime(A_aa):
        if A_aa.get("seq") == target_A_aa:
            score += 20
            a_aa_match = True
            feedback_parts.append("A Chain AA exact match")
        elif target_A_aa in A_aa.get("seq", ""):
            score += 10
            feedback_parts.append("A Chain AA sequence partially matched/embedded")
        else:
            feedback_parts.append("A Chain AA sequence incorrect")
    else:
        feedback_parts.append("A Chain AA missing or stale")

    # ================================================================
    # CRITERION 5: Header Authenticity (20 pts)
    # ================================================================
    headers = [f.get("header", "").lower() for f in [A_nt, A_aa, B_nt, B_aa] if f.get("exists")]
    valid_headers = 0
    for h in headers:
        # Check if the header contains UGENE artifact markers (mat_peptide reference, coordinate spans)
        if "mat_peptide" in h or ".." in h or "translation" in h or "[" in h or "NM_000207" in h.upper():
            valid_headers += 1
            
    if len(headers) > 0 and valid_headers == len(headers):
        score += 20
        feedback_parts.append("FASTA headers authenticated (UGENE export)")
    elif valid_headers > 0:
        score += 10
        feedback_parts.append("FASTA headers partially authenticated")
    else:
        feedback_parts.append("FASTA headers lack expected UGENE metadata (potential fabrication)")

    # ================================================================
    # CRITERION 6: Summary Report (10 pts)
    # ================================================================
    if result.get("report_exists"):
        content = result.get("report_content", "")
        if "21" in content and "30" in content:
            score += 10
            feedback_parts.append("Report contains correct lengths")
        else:
            score += 5
            feedback_parts.append("Report exists but missing correct lengths")
    else:
        feedback_parts.append("Report missing")
        
    # Optional VLM verification of Trajectory
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = (
            "Did the agent use UGENE to open the human insulin GenBank file and interact with "
            "the Sequence View or Annotations panel to isolate and export the 'mat_peptide' features? "
            "Reply with exactly 'YES' or 'NO'."
        )
        
        vlm_res = query_vlm(images=images, prompt=prompt)
        vlm_used = "YES" in vlm_res.get("response", "").upper()
        if vlm_used:
            feedback_parts.append("VLM confirms UGENE interaction")
        else:
            feedback_parts.append("VLM did not confirm visual UGENE interaction")
    except Exception as e:
        logger.info(f"VLM trajectory verification skipped/failed: {e}")

    # Pass Threshold: 70 points WITH strict AA sequence matching.
    # The AA sequences MUST perfectly match targets to guarantee the correct features were identified and exported
    key_criteria_met = (a_aa_match and b_aa_match)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }