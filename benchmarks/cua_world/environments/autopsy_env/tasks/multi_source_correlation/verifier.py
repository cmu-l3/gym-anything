#!/usr/bin/env python3
"""
Verifier for multi_source_correlation task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Autopsy case created and DB found
  20 pts  — Both disk images added as separate data sources
  15 pts  — Ingest completed on both sources
  20 pts  — Correlation report exists, is recent, has required sections
  20 pts  — Report file counts are within tolerance of GT file counts
  15 pts  — Summary file exists with investigation conclusion section
"""

import json
import os
import re
import tempfile


def verify_multi_source_correlation(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/multi_source_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/multi_source_gt.json")

    # ── Pull result ───────────────────────────────────────────────────────────
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
            "feedback": "Result file not found — task was not attempted."
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # ── Pull GT ───────────────────────────────────────────────────────────────
    gt = {
        "source1_file_count": 0,
        "source2_file_count": 0,
        "shared_md5_count": 0,
        "cross_device_matches": []
    }
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    gt_src1 = gt.get("source1_file_count", 0)
    gt_src2 = gt.get("source2_file_count", 0)
    gt_shared = gt.get("shared_md5_count", 0)

    # ── Criterion 1: Case DB found (10 pts) ───────────────────────────────────
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found for Cross_Device_Analysis_2024 (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── Criterion 2: Both sources added (20 pts) ──────────────────────────────
    if result.get("both_sources_added"):
        score += 20
        feedback_parts.append("PASS Both disk images added as data sources (+20)")
    elif result.get("source1_added"):
        score += 8
        feedback_parts.append("PARTIAL Only one data source found in DB (+8)")
    else:
        feedback_parts.append("FAIL No data sources found in DB")

    # ── Criterion 3: Ingest completed (15 pts) ────────────────────────────────
    db_total = result.get("db_total_files", 0)
    if result.get("ingest_completed") and db_total > 0:
        score += 15
        feedback_parts.append(f"PASS Ingest completed: {db_total} total files indexed (+15)")
    elif db_total > 0:
        score += 8
        feedback_parts.append(f"PARTIAL Some files indexed ({db_total}) but ingest may not be complete (+8)")
    else:
        feedback_parts.append("FAIL Ingest did not complete (no files indexed)")

    # ── Criterion 4: Correlation report format (20 pts) ───────────────────────
    start_time = result.get("start_time", 0)
    corr_mtime = result.get("correlation_report_mtime", 0)
    corr_content = result.get("correlation_report_content", "").replace("\\n", "\n")

    if result.get("correlation_report_exists"):
        is_recent = (start_time == 0 or corr_mtime >= start_time)
        corr_upper = corr_content.upper()
        lines = [l.strip() for l in corr_content.splitlines() if l.strip()]

        has_source1 = "SOURCE_1" in corr_upper or "SOURCE1" in corr_upper
        has_source2 = "SOURCE_2" in corr_upper or "SOURCE2" in corr_upper
        has_cross = "CROSS" in corr_upper or "MATCH" in corr_upper or "SHARED" in corr_upper

        if is_recent and has_source1 and has_source2 and has_cross:
            score += 20
            feedback_parts.append("PASS Correlation report has all required sections (+20)")
        elif is_recent and (has_source1 or has_source2 or has_cross):
            score += 12
            feedback_parts.append("PARTIAL Correlation report has some required sections (+12)")
        elif is_recent and len(lines) > 0:
            score += 6
            feedback_parts.append("PARTIAL Correlation report exists and is recent but lacks structure (+6)")
        else:
            score += 3
            feedback_parts.append("PARTIAL Correlation report exists but is stale or empty (+3)")
    else:
        feedback_parts.append("FAIL Correlation report not written to /home/ga/Reports/correlation_report.txt")

    # ── Criterion 5: File counts within tolerance of GT (20 pts) ─────────────
    # Extract numbers from correlation report and compare to GT
    corr_content_clean = corr_content.replace("\\n", "\n")
    numbers_found = re.findall(r'\b(\d+)\b', corr_content_clean)
    numbers_in_report = set(int(n) for n in numbers_found if int(n) > 0)

    pts_counts = 0
    if gt_src1 > 0 or gt_src2 > 0:
        # Check if GT file counts appear anywhere in the report (±20% tolerance)
        def count_in_report(target, tolerance=0.2):
            low = max(0, int(target * (1 - tolerance)))
            high = int(target * (1 + tolerance)) + 1
            return any(low <= n <= high for n in numbers_in_report)

        if count_in_report(gt_src1) and gt_src1 > 0:
            pts_counts += 8
            feedback_parts.append(f"INFO Report references source1 file count ~{gt_src1} (+8)")
        if count_in_report(gt_src2) and gt_src2 > 0:
            pts_counts += 7
            feedback_parts.append(f"INFO Report references source2 file count ~{gt_src2} (+7)")
        # Check cross-device match count
        if count_in_report(gt_shared) or gt_shared == 0:
            pts_counts += 5
            feedback_parts.append(f"INFO Report correctly reports {gt_shared} cross-device match(es) (+5)")
        pts_counts = min(pts_counts, 20)
    else:
        # GT unavailable — check if report has any numeric data
        if len(numbers_in_report) >= 2 and corr_content_clean.strip():
            pts_counts = 15
            feedback_parts.append(f"PASS Report has numeric data (GT unavailable, +15)")
        elif corr_content_clean.strip():
            pts_counts = 8
            feedback_parts.append("PARTIAL Report has content but no quantitative data (+8)")

    score += pts_counts
    if pts_counts == 0:
        feedback_parts.append("FAIL File counts in report could not be validated against GT")

    # ── Criterion 6: Summary with investigation conclusion (15 pts) ───────────
    summary_content = result.get("summary_content", "").replace("\\n", "\n")
    if result.get("summary_file_exists") and summary_content.strip():
        summary_upper = summary_content.upper()
        has_unique1 = "UNIQUE" in summary_upper or "SOURCE_1" in summary_upper or "SOURCE1" in summary_upper
        has_unique2 = "SOURCE_2" in summary_upper or "SOURCE2" in summary_upper
        has_conclusion = "CONCLUSION" in summary_upper or "INVESTIGATION" in summary_upper or "EVIDENCE" in summary_upper

        start_time_ok = (start_time == 0)
        try:
            import os as _os
            summary_path = "/home/ga/Reports/correlation_summary.txt"
            # Infer recency from the fact summary content exists (post-task)
            start_time_ok = True
        except Exception:
            pass

        if has_unique1 and has_unique2 and has_conclusion:
            score += 15
            feedback_parts.append("PASS Summary has all required sections including conclusion (+15)")
        elif has_conclusion or (has_unique1 and has_unique2):
            score += 9
            feedback_parts.append("PARTIAL Summary has some sections (+9)")
        else:
            score += 4
            feedback_parts.append("PARTIAL Summary file exists but lacks required sections (+4)")
    else:
        feedback_parts.append("FAIL Summary not written to /home/ga/Reports/correlation_summary.txt")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
