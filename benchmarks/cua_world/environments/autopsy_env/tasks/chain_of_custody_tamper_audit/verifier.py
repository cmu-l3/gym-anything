#!/usr/bin/env python3
"""
Verifier for chain_of_custody_tamper_audit task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Autopsy case created (Evidence_Audit_2024)
  10 pts  — Report file exists and was written during the task
  20 pts  — Correctly identified the TAMPERED_IMAGE
  15 pts  — Correctly reported the ORIGINAL_SHA256 from the log
  15 pts  — Correctly reported the CURRENT_SHA256
  15 pts  — Correctly identified planted file 1 (planted_evidence.txt)
  15 pts  — Correctly identified planted file 2 (confidential_informant.png)
"""

import json
import os
import re
import tempfile


def verify_chain_of_custody_audit(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/chain_of_custody_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/chain_of_custody_gt.json")

    # ── Pull result JSON ──────────────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"](result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script did not run or task was not attempted."
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # ── Pull ground truth ─────────────────────────────────────────────────────
    gt = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read ground truth: {e}"}

    gt_tampered_image = gt.get("tampered_image", "")
    gt_original_hash = gt.get("original_hash", "").lower()
    gt_current_hash = gt.get("current_hash", "").lower()
    gt_planted_files = gt.get("planted_files", [])

    # ── Criterion 1: Case DB found (10 pts) ───────────────────────────────────
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found for Evidence_Audit_2024 (+10)")
    else:
        feedback_parts.append("FAIL Case DB Evidence_Audit_2024 not found")

    # ── Criterion 2: Report Exists and Recent (10 pts) ────────────────────────
    start_time = result.get("start_time", 0)
    report_mtime = result.get("report_mtime", 0)
    report_content = result.get("report_content", "")
    
    if result.get("report_exists"):
        if start_time == 0 or report_mtime >= start_time:
            score += 10
            feedback_parts.append("PASS Report file exists and is recent (+10)")
        else:
            score += 5
            feedback_parts.append("PARTIAL Report file exists but pre-dates task start (+5)")
    else:
        feedback_parts.append("FAIL Report file integrity_audit.txt not found")

    # ── Parse Agent Report ────────────────────────────────────────────────────
    parsed_tampered = ""
    parsed_orig_hash = ""
    parsed_curr_hash = ""
    parsed_planted = ""

    match_img = re.search(r'TAMPERED_IMAGE:\s*(seized_usb_\d\.dd)', report_content, re.IGNORECASE)
    if match_img:
        parsed_tampered = match_img.group(1).strip()
        
    match_orig = re.search(r'ORIGINAL_SHA256:\s*([a-fA-F0-9]{64})', report_content, re.IGNORECASE)
    if match_orig:
        parsed_orig_hash = match_orig.group(1).strip().lower()
        
    match_curr = re.search(r'CURRENT_SHA256:\s*([a-fA-F0-9]{64})', report_content, re.IGNORECASE)
    if match_curr:
        parsed_curr_hash = match_curr.group(1).strip().lower()
        
    match_files = re.search(r'PLANTED_FILES:\s*([^\n]+)', report_content, re.IGNORECASE)
    if match_files:
        parsed_planted = match_files.group(1).strip().lower()

    # ── Criterion 3: Tampered Image (20 pts) ──────────────────────────────────
    if parsed_tampered.lower() == gt_tampered_image.lower() and gt_tampered_image != "":
        score += 20
        feedback_parts.append("PASS Correctly identified tampered image (+20)")
    else:
        feedback_parts.append(f"FAIL Tampered image incorrect. Expected {gt_tampered_image}, found '{parsed_tampered}'")

    # ── Criterion 4: Original Hash (15 pts) ───────────────────────────────────
    if parsed_orig_hash == gt_original_hash and gt_original_hash != "":
        score += 15
        feedback_parts.append("PASS Correctly extracted original hash from log (+15)")
    else:
        feedback_parts.append("FAIL Original hash incorrect or missing")

    # ── Criterion 5: Current Hash (15 pts) ────────────────────────────────────
    if parsed_curr_hash == gt_current_hash and gt_current_hash != "":
        score += 15
        feedback_parts.append("PASS Correctly computed current hash of tampered drive (+15)")
    else:
        feedback_parts.append("FAIL Current hash incorrect or missing")

    # ── Criterion 6 & 7: Planted Files (15 pts each) ──────────────────────────
    if gt_planted_files:
        file_1 = gt_planted_files[0].lower()
        file_2 = gt_planted_files[1].lower() if len(gt_planted_files) > 1 else "MISSING"
        
        if file_1 in parsed_planted:
            score += 15
            feedback_parts.append(f"PASS Identified planted file: {file_1} (+15)")
        else:
            feedback_parts.append(f"FAIL Missed planted file: {file_1}")
            
        if file_2 in parsed_planted:
            score += 15
            feedback_parts.append(f"PASS Identified planted file: {file_2} (+15)")
        else:
            feedback_parts.append(f"FAIL Missed planted file: {file_2}")

    # ── Final Determination ───────────────────────────────────────────────────
    passed = score >= 60
    
    # Optional VLM integration note
    feedback_parts.append("Note: Verification relied on hard cryptographic proofs & metadata limits.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }