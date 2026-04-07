#!/usr/bin/env python3
"""
Verifier for communications_network_graph_analysis task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Autopsy case created and DB found
  20 pts  — Email data source added and parsed (TSK_EMAIL_MSG artifacts exist)
  10 pts  — Report file exists, is recent, and has the basic structure
  10 pts  — Total emails parsed matches GT within 10%
  30 pts  — Identified Top 3 communicators match the top 3 in GT (10 pts each, order-independent)
  20 pts  — The counts provided for the Top 3 match GT within a small tolerance (10%)
"""

import json
import os
import re
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm


def extract_report_data(report_content):
    """Parse the agent's text report to extract counts and communicators."""
    data = {
        "total_parsed": None,
        "top_communicators": []
    }
    
    # Extract total emails
    total_match = re.search(r'TOTAL_EMAILS_PARSED:\s*(\d+)', report_content, re.IGNORECASE)
    if total_match:
        data["total_parsed"] = int(total_match.group(1))
        
    # Extract top communicators (looking for lines like "1. email@domain.com | 150")
    for line in report_content.split('\n'):
        # Match lines starting with a digit, optionally a dot, an email, a pipe, and a number
        comm_match = re.match(r'^\d+\.?\s+([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})\s*\|\s*(\d+)', line.strip())
        if comm_match:
            data["top_communicators"].append({
                "email": comm_match.group(1).lower(),
                "count": int(comm_match.group(2))
            })
            
    return data


def verify_network_analysis(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/network_analysis_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/network_analysis_gt.json")

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier error: copy_from_env not available."}

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
            "feedback": "Result file not found — export script did not run or task was not attempted."
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    # ── Pull ground truth from VM ──────────────────────────────────────────────
    gt = {"total_emails": 0, "top_communicators": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        copy_from_env(gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    # ── Criterion 1: Case DB found (10 pts) ───────────────────────────────────
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── Criterion 2: Data Source & Email Parsing (20 pts) ─────────────────────
    if result.get("data_source_added") and result.get("email_artifacts_found", 0) > 0:
        score += 20
        feedback_parts.append(f"PASS MBOX ingested and {result['email_artifacts_found']} email artifacts generated (+20)")
    else:
        feedback_parts.append("FAIL Email Parser ingest did not run or failed to generate artifacts")

    # ── Parse the Agent's Report ──────────────────────────────────────────────
    report_exists = result.get("report_file_exists", False)
    start_time = result.get("start_time", 0)
    report_mtime = result.get("report_mtime", 0)
    
    if not report_exists:
        feedback_parts.append("FAIL Report file /home/ga/Reports/communicator_analysis.txt not found")
        # Early exit evaluation of remaining criteria
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    if report_mtime < start_time and start_time > 0:
        feedback_parts.append("FAIL Report file is stale (created before task started)")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    report_data = extract_report_data(result.get("report_content", ""))

    # ── Criterion 3: Report Structure (10 pts) ────────────────────────────────
    if report_data["total_parsed"] is not None and len(report_data["top_communicators"]) > 0:
        score += 10
        feedback_parts.append("PASS Report structure is valid (+10)")
    else:
        feedback_parts.append("FAIL Report lacks TOTAL_EMAILS_PARSED or TOP_COMMUNICATORS format")

    # ── Criterion 4: Total Emails Match (10 pts) ──────────────────────────────
    gt_total = gt.get("total_emails", 0)
    rep_total = report_data["total_parsed"]
    
    if gt_total > 0 and rep_total is not None:
        # Allow a 10% tolerance for different parser nuances between mailbox and Autopsy
        if abs(gt_total - rep_total) / gt_total <= 0.10:
            score += 10
            feedback_parts.append(f"PASS Total emails parsed ({rep_total}) matches GT ({gt_total}) (+10)")
        else:
            feedback_parts.append(f"FAIL Total emails ({rep_total}) deviates too much from GT ({gt_total})")

    # ── Criterion 5 & 6: Top 3 Matches and Counts (50 pts total) ──────────────
    gt_top = gt.get("top_communicators", [])
    if len(gt_top) >= 3:
        gt_top_3_emails = [c["email"].lower() for c in gt_top[:3]]
        gt_counts_map = {c["email"].lower(): c["count"] for c in gt_top}
        
        rep_emails = [c["email"].lower() for c in report_data["top_communicators"][:3]]
        
        # 10 points per matched email address
        matched_emails = 0
        counts_accurate = 0
        
        for rep_comm in report_data["top_communicators"][:3]:
            em = rep_comm["email"]
            c_val = rep_comm["count"]
            
            if em in gt_top_3_emails:
                matched_emails += 1
                score += 10
                
                # Verify count (allow 10% tolerance for Autopsy UI grouping vs raw mailbox count)
                gt_c = gt_counts_map[em]
                if abs(gt_c - c_val) <= max(3, gt_c * 0.10):
                    counts_accurate += 1
                    
        feedback_parts.append(f"PASS Identified {matched_emails}/3 top communicators correctly (+{matched_emails*10})")
        
        # Award up to 20 pts proportionally for count accuracy
        if matched_emails > 0:
            count_pts = int((counts_accurate / matched_emails) * 20)
            score += count_pts
            feedback_parts.append(f"PASS {counts_accurate}/{matched_emails} counts were within tolerance (+{count_pts})")

    # Final pass/fail determination
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }