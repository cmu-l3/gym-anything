#!/usr/bin/env python3
"""
Verifier for deleted_evidence_recovery task.

Scoring (100 pts total, pass threshold = 60):
  15 pts  — Autopsy case created and DB found
  15 pts  — Disk image data source added to case
  10 pts  — Ingest completed (files indexed in DB)
  20 pts  — Deleted files detected in Autopsy DB (count within tolerance of GT)
  15 pts  — Agent's forensic report file exists and is newer than task start
  25 pts  — Report content matches ground-truth deleted file names (≥50% coverage)
"""

import json
import os
import re
import tempfile


def verify_deleted_evidence_recovery(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/deleted_evidence_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/deleted_evidence_gt.json")

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
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file: {e}"
        }

    # ── Pull ground truth from VM ──────────────────────────────────────────────
    gt = {"deleted_files": [], "total_deleted": 0, "deleted_names": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass  # GT unavailable — fall back to DB-only checks

    gt_names = set(n.lower() for n in gt.get("deleted_names", []))
    gt_total = gt.get("total_deleted", 0)

    # ── Criterion 1: Case DB found (15 pts) ───────────────────────────────────
    if result.get("case_db_found") and result.get("case_name_matches"):
        score += 15
        feedback_parts.append("PASS Case DB found for Deleted_Evidence_2024 (+15)")
    else:
        feedback_parts.append("FAIL Case DB not found — case may not have been created")

    # ── Criterion 2: Data source added (15 pts) ───────────────────────────────
    if result.get("data_source_added"):
        score += 15
        feedback_parts.append("PASS Data source (disk image) added to case (+15)")
    else:
        feedback_parts.append("FAIL Data source not found in case DB")

    # ── Criterion 3: Ingest completed (10 pts) ────────────────────────────────
    if result.get("ingest_completed"):
        score += 10
        feedback_parts.append("PASS Ingest completed — allocated files indexed (+10)")
    else:
        feedback_parts.append("FAIL Ingest did not complete or no allocated files found in DB")

    # ── Criterion 4: Deleted files detected (20 pts) ─────────────────────────
    db_count = result.get("db_deleted_file_count", 0)
    if gt_total > 0:
        if db_count >= gt_total - 1:
            score += 20
            feedback_parts.append(
                f"PASS Correct number of deleted files in DB: {db_count} (GT={gt_total}) (+20)"
            )
        elif db_count >= max(1, gt_total // 2):
            score += 10
            feedback_parts.append(
                f"PARTIAL Partial deleted files in DB: {db_count}/{gt_total} (+10)"
            )
        else:
            feedback_parts.append(
                f"FAIL Too few deleted files in DB: {db_count}/{gt_total}"
            )
    else:
        # GT unavailable — award points if agent found any deleted files
        if db_count >= 1:
            score += 15
            feedback_parts.append(f"PASS {db_count} deleted file(s) detected in DB (+15, no GT)")
        else:
            feedback_parts.append("FAIL No deleted files found in DB")

    # ── Criterion 5: Report file exists and is recent (15 pts) ───────────────
    start_time = result.get("start_time", 0)
    report_mtime = result.get("report_mtime", 0)
    if result.get("report_file_exists"):
        if start_time == 0 or report_mtime >= start_time:
            score += 15
            feedback_parts.append("PASS Forensic report file exists and was written during task (+15)")
        else:
            score += 5
            feedback_parts.append(
                "PARTIAL Report file exists but pre-dates task start (may be stale) (+5)"
            )
    else:
        feedback_parts.append("FAIL Forensic report not written to /home/ga/Reports/deleted_evidence_report.txt")

    # ── Criterion 6: Report content matches GT names (25 pts) ────────────────
    report_content = result.get("report_content", "")
    # Unescape JSON-escaped newlines (from export script serialization)
    report_content = report_content.replace("\\n", "\n").replace("\\t", "\t")

    if report_content.strip() and gt_names:
        lines = [l.strip() for l in report_content.splitlines() if l.strip()]
        # Count how many GT names appear in report
        matched = 0
        for name in gt_names:
            if any(name in line.lower() for line in lines):
                matched += 1
        coverage = matched / len(gt_names) if gt_names else 0

        if coverage >= 0.8:
            score += 25
            feedback_parts.append(
                f"PASS Report covers {matched}/{len(gt_names)} GT deleted files ({coverage:.0%}) (+25)"
            )
        elif coverage >= 0.5:
            score += 15
            feedback_parts.append(
                f"PARTIAL Report covers {matched}/{len(gt_names)} GT files ({coverage:.0%}) (+15)"
            )
        elif coverage >= 0.25:
            score += 8
            feedback_parts.append(
                f"PARTIAL Report covers {matched}/{len(gt_names)} GT files ({coverage:.0%}) (+8)"
            )
        else:
            # Check if report has pipe-delimited lines at all (attempted correct format)
            pipe_lines = [l for l in lines if "|" in l]
            if pipe_lines:
                score += 3
                feedback_parts.append(
                    f"PARTIAL Report has {len(pipe_lines)} pipe-delimited lines but names don't match GT (+3)"
                )
            else:
                feedback_parts.append("FAIL Report does not contain expected deleted file names")
    elif report_content.strip() and not gt_names:
        # GT unavailable — check for pipe-delimited lines as a proxy
        lines = [l.strip() for l in report_content.splitlines() if "|" in l.strip()]
        if len(lines) >= 1:
            score += 20
            feedback_parts.append(
                f"PASS Report has {len(lines)} pipe-delimited entries (GT unavailable, awarding +20)"
            )
        else:
            score += 5
            feedback_parts.append("PARTIAL Report exists but lacks expected pipe-delimited format (+5)")
    else:
        feedback_parts.append("FAIL Report is empty or not written")

    # ── Bonus: exported files (up to 0 pts, just for feedback) ───────────────
    export_count = result.get("export_dir_file_count", 0)
    if export_count > 0:
        feedback_parts.append(f"INFO {export_count} file(s) exported to /home/ga/Reports/deleted_evidence/")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
