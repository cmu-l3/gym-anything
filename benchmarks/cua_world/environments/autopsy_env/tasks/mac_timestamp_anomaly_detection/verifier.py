#!/usr/bin/env python3
"""
Verifier for mac_timestamp_anomaly_detection task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Autopsy case created and DB found
  10 pts  — Disk image data source added
  5  pts  — Ingest completed
  10 pts  — Timestamp CSV exists, is recent, and uses pipe-delimiters
  15 pts  — CSV file count within ±20% of GT
  10 pts  — CSV covers ≥50% of GT filenames
  10 pts  — Anomaly report exists with all 9 required sections
  10 pts  — Activity window dates approximately match GT (year bounds)
  10 pts  — Allocated/deleted totals within ±20% of GT
  10 pts  — Anomaly counts (Cr>Mod, Future, Pre-2000) within ±2 of GT
"""

import json
import os
import re
import tempfile


def extract_count(text, prefix):
    """Extract an integer count following a specific prefix in text."""
    pattern = rf"{prefix}\s*[:\-]?\s*(\d+)"
    match = re.search(pattern, text, re.IGNORECASE)
    if match:
        return int(match.group(1))
    return None


def extract_dates(text):
    """Extract dates from VOLUME_ACTIVITY_WINDOW section."""
    pattern = r"VOLUME_ACTIVITY_WINDOW\s*[:\-]?\s*(\d{4}-\d{2}-\d{2})\s*(?:to|-)\s*(\d{4}-\d{2}-\d{2})"
    match = re.search(pattern, text, re.IGNORECASE)
    if match:
        return match.group(1), match.group(2)
    return None, None


def verify_mac_timestamp_anomaly_detection(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/mac_anomaly_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/mac_anomaly_gt.json")

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
        return {"passed": False, "score": 0, "feedback": "Result file not found."}
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
    except Exception:
        pass

    gt_total = gt.get("total_files", 0)
    gt_alloc = gt.get("total_allocated", 0)
    gt_del = gt.get("total_deleted", 0)
    gt_crmod = gt.get("anomaly_created_after_modified", 0)
    gt_future = gt.get("anomaly_future_timestamps", 0)
    gt_pre2k = gt.get("anomaly_pre_2000_timestamps", 0)
    gt_names = set(n.lower() for n in gt.get("filenames", []))

    start_time = result.get("start_time", 0)

    # ── 1. Case DB (10) ───────────────────────────────────────────────────────
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── 2. Data source added (10) ─────────────────────────────────────────────
    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added (+10)")
    else:
        feedback_parts.append("FAIL Data source not added")

    # ── 3. Ingest completed (5) ───────────────────────────────────────────────
    if result.get("ingest_completed"):
        score += 5
        feedback_parts.append("PASS Ingest completed (+5)")
    else:
        feedback_parts.append("FAIL Ingest not completed")

    # ── 4 & 5. CSV format (10) & Count (15) ───────────────────────────────────
    csv_exists = result.get("csv_file_exists", False)
    csv_content = result.get("csv_content", "").replace("\\n", "\n")
    csv_lines = [l.strip() for l in csv_content.splitlines() if l.strip()]
    csv_data_lines = [l for l in csv_lines if "|" in l and "FILENAME" not in l.upper()]

    if csv_exists and (start_time == 0 or result.get("csv_mtime", 0) >= start_time):
        if len(csv_data_lines) > 0:
            score += 10
            feedback_parts.append("PASS CSV is recent and pipe-delimited (+10)")
            
            # Count check
            csv_count = len(csv_data_lines)
            if gt_total > 0:
                if abs(csv_count - gt_total) <= max(2, int(gt_total * 0.20)):
                    score += 15
                    feedback_parts.append(f"PASS CSV count {csv_count} within 20% of GT {gt_total} (+15)")
                elif abs(csv_count - gt_total) <= max(5, int(gt_total * 0.50)):
                    score += 7
                    feedback_parts.append(f"PARTIAL CSV count {csv_count} vs GT {gt_total} (+7)")
                else:
                    feedback_parts.append(f"FAIL CSV count {csv_count} too far from GT {gt_total}")
            else:
                score += 15
                feedback_parts.append("PASS CSV populated (No GT available) (+15)")
        else:
            feedback_parts.append("FAIL CSV exists but lacks pipe-delimited data")
    else:
        feedback_parts.append("FAIL CSV missing or stale")

    # ── 6. CSV Coverage (10) ──────────────────────────────────────────────────
    if csv_exists and gt_names:
        csv_lower = csv_content.lower()
        matched = sum(1 for name in gt_names if name in csv_lower)
        coverage = matched / len(gt_names)
        if coverage >= 0.5:
            score += 10
            feedback_parts.append(f"PASS CSV covers {coverage:.0%} of GT names (+10)")
        elif coverage >= 0.2:
            score += 5
            feedback_parts.append(f"PARTIAL CSV covers {coverage:.0%} of GT names (+5)")
        else:
            feedback_parts.append(f"FAIL CSV covers only {coverage:.0%} of GT names")
    elif csv_exists:
        score += 10
        feedback_parts.append("PASS CSV coverage awarded (No GT names available) (+10)")

    # ── 7. Anomaly Report Sections (10) ───────────────────────────────────────
    report_exists = result.get("report_file_exists", False)
    report_content = result.get("report_content", "")
    report_upper = report_content.upper()

    req_sections = [
        "VOLUME_ACTIVITY_WINDOW", "TOTAL_FILES_ANALYZED", "TOTAL_ALLOCATED",
        "TOTAL_DELETED", "ANOMALY_CREATED_AFTER_MODIFIED", "ANOMALY_FUTURE_TIMESTAMPS",
        "ANOMALY_PRE_2000_TIMESTAMPS", "ANOMALY_SI_FN_DIVERGENCE", "FINDINGS"
    ]

    if report_exists and (start_time == 0 or result.get("report_mtime", 0) >= start_time):
        found_sections = sum(1 for s in req_sections if s in report_upper)
        if found_sections == len(req_sections):
            score += 10
            feedback_parts.append("PASS Report contains all required sections (+10)")
        elif found_sections >= 5:
            score += 5
            feedback_parts.append(f"PARTIAL Report contains {found_sections}/{len(req_sections)} sections (+5)")
        else:
            feedback_parts.append(f"FAIL Report missing most sections ({found_sections}/{len(req_sections)})")
    else:
        feedback_parts.append("FAIL Report file missing or stale")

    # ── 8. Dates (10) ─────────────────────────────────────────────────────────
    if report_exists:
        rep_start, rep_end = extract_dates(report_content)
        gt_start = gt.get("earliest_date", "")
        gt_end = gt.get("latest_date", "")
        
        if rep_start and rep_end and gt_start and gt_end:
            # Check if year matches to allow some variance
            if rep_start[:4] == gt_start[:4] and rep_end[:4] == gt_end[:4]:
                score += 10
                feedback_parts.append("PASS Activity dates approx correct (+10)")
            else:
                score += 5
                feedback_parts.append(f"PARTIAL Activity dates extracted but mismatch GT: {rep_start}/{rep_end} vs {gt_start}/{gt_end} (+5)")
        else:
            # Fallback if parsing failed but GT wasn't strict
            feedback_parts.append("FAIL Could not parse activity window dates")
            
    # ── 9. Alloc/Del Totals (10) ──────────────────────────────────────────────
    if report_exists:
        rep_alloc = extract_count(report_content, "TOTAL_ALLOCATED")
        rep_del = extract_count(report_content, "TOTAL_DELETED")
        
        if rep_alloc is not None and rep_del is not None:
            alloc_diff = abs(rep_alloc - gt_alloc)
            del_diff = abs(rep_del - gt_del)
            
            if alloc_diff <= max(2, int(gt_alloc * 0.2)) and del_diff <= max(2, int(gt_del * 0.2)):
                score += 10
                feedback_parts.append(f"PASS Allocated/Deleted counts within tolerance (+10)")
            else:
                score += 5
                feedback_parts.append(f"PARTIAL Alloc/Del counts somewhat inaccurate: {rep_alloc}/{rep_del} vs {gt_alloc}/{gt_del} (+5)")
        else:
            feedback_parts.append("FAIL Could not parse Allocated/Deleted counts")

    # ── 10. Anomaly Counts (10) ───────────────────────────────────────────────
    if report_exists:
        rep_crmod = extract_count(report_content, "ANOMALY_CREATED_AFTER_MODIFIED")
        rep_fut = extract_count(report_content, "ANOMALY_FUTURE_TIMESTAMPS")
        rep_pre2k = extract_count(report_content, "ANOMALY_PRE_2000_TIMESTAMPS")
        
        if rep_crmod is not None and rep_fut is not None and rep_pre2k is not None:
            # Allowing ±2 tolerance on these specific anomaly queries
            if (abs(rep_crmod - gt_crmod) <= 2 and 
                abs(rep_fut - gt_future) <= 2 and 
                abs(rep_pre2k - gt_pre2k) <= 2):
                score += 10
                feedback_parts.append("PASS Anomaly counts match GT within tolerance (+10)")
            else:
                score += 5
                feedback_parts.append(f"PARTIAL Anomaly counts differ from GT: Cr>Mod {rep_crmod}/{gt_crmod}, Fut {rep_fut}/{gt_future}, Pre2k {rep_pre2k}/{gt_pre2k} (+5)")
        else:
            feedback_parts.append("FAIL Could not parse Anomaly counts from report")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }