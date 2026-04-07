#!/usr/bin/env python3
"""
Verifier for forensic_cross_validation task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Case DB found with correct name
  10 pts  — Data source added
  5 pts   — Ingest completed
  10 pts  — TSK raw output exists and contains fls formatting
  10 pts  — TSK inventory file exists, is recent, and well-formed
  10 pts  — Autopsy inventory file exists, is recent, and well-formed
  15 pts  — Cross-validation report contains all required sections
  10 pts  — Report file counts are within tolerance of GT
  15 pts  — Hash verifications match ground truth MD5 computations
  5 pts   — QA conclusion is present
"""

import json
import os
import re
import tempfile

def verify_forensic_cross_validation(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/crossval_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/crossval_gt.json")

    # ── Pull result JSON from VM ──────────────────────────────────────────────
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
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    # ── Pull ground truth from VM ──────────────────────────────────────────────
    gt = {"total_files": 0, "hashes": {}}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    start_time = result.get("start_time", 0)

    # ── Criterion 1: Case DB found (10 pts) ───────────────────────────────────
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── Criterion 2: Data source added (10 pts) ───────────────────────────────
    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added (+10)")
    else:
        feedback_parts.append("FAIL Data source not found")

    # ── Criterion 3: Ingest completed (5 pts) ─────────────────────────────────
    if result.get("ingest_completed"):
        score += 5
        feedback_parts.append("PASS Ingest completed (+5)")
    else:
        feedback_parts.append("FAIL Ingest did not complete")

    # ── Criterion 4: TSK raw output (10 pts) ──────────────────────────────────
    if result.get("tsk_raw_exists"):
        is_recent = (start_time == 0 or result.get("tsk_raw_mtime", 0) >= start_time)
        content = result.get("tsk_raw_content", "")
        if is_recent and ("r/r" in content or "d/d" in content) and ":" in content:
            score += 10
            feedback_parts.append("PASS TSK raw output contains fls data (+10)")
        elif is_recent:
            score += 5
            feedback_parts.append("PARTIAL TSK raw output exists but format unrecognized (+5)")
        else:
            feedback_parts.append("FAIL TSK raw output is stale")
    else:
        feedback_parts.append("FAIL TSK raw output not found")

    # ── Criterion 5: TSK inventory file (10 pts) ──────────────────────────────
    if result.get("tsk_inv_exists"):
        is_recent = (start_time == 0 or result.get("tsk_inv_mtime", 0) >= start_time)
        lines = [l for l in result.get("tsk_inv_content", "").splitlines() if l.strip()]
        if is_recent and len(lines) >= 5 and "|" in lines[0]:
            score += 10
            feedback_parts.append("PASS TSK inventory file well-formed (+10)")
        elif is_recent and len(lines) > 0:
            score += 5
            feedback_parts.append("PARTIAL TSK inventory exists but may lack format/entries (+5)")
    else:
        feedback_parts.append("FAIL TSK inventory not found")

    # ── Criterion 6: Autopsy inventory file (10 pts) ──────────────────────────
    if result.get("aut_inv_exists"):
        is_recent = (start_time == 0 or result.get("aut_inv_mtime", 0) >= start_time)
        lines = [l for l in result.get("aut_inv_content", "").splitlines() if l.strip()]
        if is_recent and len(lines) >= 5 and "|" in lines[0]:
            score += 10
            feedback_parts.append("PASS Autopsy inventory file well-formed (+10)")
        elif is_recent and len(lines) > 0:
            score += 5
            feedback_parts.append("PARTIAL Autopsy inventory exists but may lack format/entries (+5)")
    else:
        feedback_parts.append("FAIL Autopsy inventory not found")

    # ── Criterion 7: Report sections (15 pts) ─────────────────────────────────
    rep_content = result.get("report_content", "")
    sections = [
        "IMAGE_METADATA:", "TSK_FILE_COUNT:", "AUTOPSY_FILE_COUNT:",
        "TSK_ALLOCATED:", "TSK_DELETED:", "AUTOPSY_ALLOCATED:",
        "AUTOPSY_DELETED:", "DISCREPANCIES:", "HASH_VERIFICATIONS:", "QA_CONCLUSION:"
    ]
    if result.get("report_exists"):
        is_recent = (start_time == 0 or result.get("report_mtime", 0) >= start_time)
        found_sections = [s for s in sections if s in rep_content]
        if is_recent and len(found_sections) == len(sections):
            score += 15
            feedback_parts.append("PASS All report sections found (+15)")
        elif is_recent and len(found_sections) >= 5:
            score += 7
            feedback_parts.append(f"PARTIAL Only {len(found_sections)}/{len(sections)} sections found (+7)")
        elif not is_recent:
            feedback_parts.append("FAIL Report file is stale")
        else:
            feedback_parts.append("FAIL Report file missing required sections")
    else:
        feedback_parts.append("FAIL Report file not found")

    # ── Criterion 8: File counts reasonable (10 pts) ──────────────────────────
    tsk_cnt_match = re.search(r'TSK_FILE_COUNT:\s*(\d+)', rep_content)
    if tsk_cnt_match and gt.get("total_files", 0) > 0:
        cnt = int(tsk_cnt_match.group(1))
        expected = gt["total_files"]
        if expected * 0.7 <= cnt <= expected * 1.3:
            score += 10
            feedback_parts.append(f"PASS TSK_FILE_COUNT ({cnt}) within tolerance of GT ({expected}) (+10)")
        else:
            feedback_parts.append(f"FAIL TSK_FILE_COUNT ({cnt}) outside tolerance of GT ({expected})")
    elif tsk_cnt_match:
        score += 5
        feedback_parts.append("PARTIAL TSK_FILE_COUNT present but GT unavailable (+5)")

    # ── Criterion 9: Hash verifications (15 pts) ──────────────────────────────
    # Format expected: INODE <n>: <filename> MD5=<hash> MATCH=YES/NO
    hash_lines = re.findall(r'INODE\s+(\d+).*?MD5=([a-fA-F0-9]{32})', rep_content, re.IGNORECASE)
    valid_hashes = 0
    gt_hashes = gt.get("hashes", {})
    
    for inode_str, md5 in hash_lines:
        if inode_str in gt_hashes and gt_hashes[inode_str].lower() == md5.lower():
            valid_hashes += 1
            
    if valid_hashes >= 3:
        score += 15
        feedback_parts.append(f"PASS {valid_hashes} hashes correctly verified against GT (+15)")
    elif valid_hashes >= 1:
        score += 7
        feedback_parts.append(f"PARTIAL {valid_hashes} hashes correctly verified (+7)")
    elif len(hash_lines) > 0:
        feedback_parts.append("FAIL Hash verifications present but hashes incorrect")
    else:
        feedback_parts.append("FAIL No valid hash verifications found in report")

    # ── Criterion 10: QA Conclusion (5 pts) ───────────────────────────────────
    if "VERIFIED" in rep_content or "DISCREPANCIES_FOUND" in rep_content:
        score += 5
        feedback_parts.append("PASS QA conclusion present (+5)")
    else:
        feedback_parts.append("FAIL QA conclusion missing")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }