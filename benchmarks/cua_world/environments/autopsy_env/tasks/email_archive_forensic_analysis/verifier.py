#!/usr/bin/env python3
"""
Verifier for email_archive_forensic_analysis task.

Scoring (100 pts total, pass threshold = 60):
  20 pts  — Case & Data Source Setup: Autopsy case exists and Logical File added.
  20 pts  — Email Parser Execution: TSK_EMAIL_MSG artifacts populated in DB (Anti-gaming).
  10 pts  — Report Structure: Report file exists and has required headers.
  20 pts  — Total Volume Accuracy: Reported email count within 5% of GT.
  30 pts  — Sender Profiling Accuracy: At least 3 of the GT top 5 senders identified.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_email_archive_forensic_analysis(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/email_task_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/email_gt.json")
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ── Pull result JSON from VM ──────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script did not run."
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file: {e}"
        }

    # ── Pull Ground Truth from VM ─────────────────────────────────────────────
    gt = {"total_emails": 0, "top_5_senders": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        copy_from_env(gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception as e:
        logger.warning(f"Could not load GT file: {e}")

    gt_total = gt.get("total_emails", 0)
    gt_top_senders = [s["email"].lower() for s in gt.get("top_5_senders", [])]

    # ── CRITICAL ANTI-GAMING: Did they actually use Autopsy? ──────────────────
    used_autopsy = result.get("email_parser_executed", False)
    if not used_autopsy:
        feedback_parts.append("CRITICAL FAIL: Email parser was not executed in Autopsy (no artifacts found).")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # ── Criterion 1: Case & Data Source (20 pts) ──────────────────────────────
    if result.get("case_db_found") and result.get("logical_file_added"):
        score += 20
        feedback_parts.append("PASS Case created and Logical File added (+20)")
    elif result.get("case_db_found"):
        score += 10
        feedback_parts.append("PARTIAL Case created, but MBOX not added as Logical File (+10)")
    else:
        feedback_parts.append("FAIL Autopsy case not found")

    # ── Criterion 2: Email Parser Execution (20 pts) ──────────────────────────
    db_email_count = result.get("db_email_artifact_count", 0)
    if db_email_count > 0:
        score += 20
        feedback_parts.append(f"PASS Email Parser executed: {db_email_count} artifacts in DB (+20)")

    # ── Criterion 3: Report Structure (10 pts) ────────────────────────────────
    report_exists = result.get("report_file_exists", False)
    report_content = result.get("report_content", "")
    start_time = result.get("start_time", 0)
    report_mtime = result.get("report_mtime", 0)
    
    if report_exists and (start_time == 0 or report_mtime >= start_time):
        if "TOTAL_EMAILS_PARSED" in report_content and "TOP_5_SENDERS" in report_content:
            score += 10
            feedback_parts.append("PASS Report file formatted correctly (+10)")
        else:
            score += 5
            feedback_parts.append("PARTIAL Report exists but missing required headers (+5)")
    else:
        feedback_parts.append("FAIL Report file not found or stale")

    # ── Criterion 4: Total Volume Accuracy (20 pts) ───────────────────────────
    if report_exists:
        match = re.search(r"TOTAL_EMAILS_PARSED:\s*(\d+)", report_content, re.IGNORECASE)
        if match:
            reported_total = int(match.group(1))
            # Allow 5% tolerance
            if gt_total > 0 and abs(reported_total - gt_total) <= (gt_total * 0.05):
                score += 20
                feedback_parts.append(f"PASS Reported total ({reported_total}) matches GT ({gt_total}) (+20)")
            else:
                feedback_parts.append(f"FAIL Reported total ({reported_total}) incorrect. Expected ~{gt_total}")
        else:
            feedback_parts.append("FAIL Could not extract TOTAL_EMAILS_PARSED from report")

    # ── Criterion 5: Sender Profiling Accuracy (30 pts) ───────────────────────
    if report_exists and gt_top_senders:
        # Extract text after TOP_5_SENDERS
        parts = re.split(r"TOP_5_SENDERS:?", report_content, flags=re.IGNORECASE)
        if len(parts) > 1:
            top_senders_text = parts[1].lower()
            matches_found = 0
            for sender in gt_top_senders:
                if sender in top_senders_text:
                    matches_found += 1
            
            if matches_found >= 3:
                score += 30
                feedback_parts.append(f"PASS {matches_found}/{len(gt_top_senders)} GT top senders identified (+30)")
            elif matches_found > 0:
                score += (matches_found * 10)
                feedback_parts.append(f"PARTIAL {matches_found}/{len(gt_top_senders)} GT top senders identified (+{matches_found * 10})")
            else:
                feedback_parts.append("FAIL No GT top senders identified in the report")
        else:
            feedback_parts.append("FAIL TOP_5_SENDERS section not found or empty")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }