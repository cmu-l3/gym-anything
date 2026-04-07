#!/usr/bin/env python3
"""
Verifier for file_system_timeline task.

Scoring (100 pts total, pass threshold = 80):
  15 pts  — Autopsy case created and DB found
  15 pts  — Disk image data source added
  10 pts  — Ingest completed
  20 pts  — Timeline CSV file exists, is recent, and has pipe-delimited data rows
  15 pts  — Timeline CSV covers ≥3 distinct files from GT file list
  25 pts  — Narrative report contains all 4 required sections
"""

import json
import os
import re
import tempfile


_REQUIRED_SECTIONS = [
    "DATE_RANGE",
    "TOTAL_EVENTS",
    "TOP_5_RECENT",
    "DELETION_EVIDENCE",
]


def verify_file_system_timeline(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/file_system_timeline_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/file_system_timeline_gt.json")

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
    gt = {"all_files": [], "total_files": 0, "most_recent_files": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    gt_names = set(f["name"].lower() for f in gt.get("all_files", []))

    # ── Criterion 1: Case DB found (15 pts) ───────────────────────────────────
    if result.get("case_db_found"):
        score += 15
        feedback_parts.append("PASS Case DB found for Timeline_Analysis_2024 (+15)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── Criterion 2: Data source added (15 pts) ───────────────────────────────
    if result.get("data_source_added"):
        score += 15
        feedback_parts.append("PASS Data source added (+15)")
    else:
        feedback_parts.append("FAIL Data source not found in DB")

    # ── Criterion 3: Ingest completed (10 pts) ────────────────────────────────
    if result.get("ingest_completed"):
        score += 10
        feedback_parts.append("PASS Ingest completed (+10)")
    else:
        feedback_parts.append("FAIL Ingest did not complete")

    # ── Criterion 4: Timeline CSV format (20 pts) ─────────────────────────────
    start_time = result.get("start_time", 0)
    csv_mtime = result.get("timeline_csv_mtime", 0)
    csv_content = result.get("timeline_csv_content", "").replace("\\n", "\n").replace("\\t", "\t")

    if result.get("timeline_csv_exists"):
        is_recent = (start_time == 0 or csv_mtime >= start_time)
        lines = [l.strip() for l in csv_content.splitlines() if l.strip()]
        has_header = any("DATETIME" in l.upper() or "FILENAME" in l.upper() or "DATE" in l.upper()
                        for l in lines[:3])
        pipe_data_lines = [l for l in lines if "|" in l and "DATETIME" not in l.upper()]

        if is_recent and has_header and len(pipe_data_lines) >= 3:
            score += 20
            feedback_parts.append(
                f"PASS Timeline CSV has header + {len(pipe_data_lines)} data rows (+20)"
            )
        elif is_recent and (has_header or len(pipe_data_lines) >= 1):
            score += 12
            feedback_parts.append(
                f"PARTIAL Timeline CSV has data but may lack proper header/structure (+12)"
            )
        elif result.get("timeline_csv_line_count", 0) > 1:
            score += 6
            feedback_parts.append(
                f"PARTIAL Timeline CSV has {result['timeline_csv_line_count']} lines but wrong format (+6)"
            )
        else:
            score += 3
            feedback_parts.append("PARTIAL Timeline CSV exists but is empty or stale (+3)")
    else:
        feedback_parts.append("FAIL Timeline CSV not written to /home/ga/Reports/fs_timeline.csv")

    # ── Criterion 5: CSV covers GT files (15 pts) ─────────────────────────────
    if csv_content.strip() and gt_names:
        csv_lower = csv_content.lower()
        matched = sum(1 for name in gt_names if name in csv_lower)
        coverage = matched / len(gt_names) if gt_names else 0

        if coverage >= 0.5:
            score += 15
            feedback_parts.append(
                f"PASS Timeline CSV covers {matched}/{len(gt_names)} GT files ({coverage:.0%}) (+15)"
            )
        elif matched >= 3:
            score += 10
            feedback_parts.append(
                f"PARTIAL Timeline CSV covers {matched}/{len(gt_names)} GT files (+10)"
            )
        elif matched >= 1:
            score += 5
            feedback_parts.append(
                f"PARTIAL Timeline CSV covers {matched}/{len(gt_names)} GT files (+5)"
            )
        else:
            feedback_parts.append("FAIL Timeline CSV does not reference expected file names")
    elif csv_content.strip() and not gt_names:
        pipe_lines = [l for l in csv_content.splitlines() if "|" in l]
        if len(pipe_lines) >= 3:
            score += 12
            feedback_parts.append(f"PASS CSV has {len(pipe_lines)} pipe-delimited rows (GT unavailable, +12)")
    else:
        feedback_parts.append("FAIL Timeline CSV is empty")

    # ── Criterion 6: Narrative report sections (25 pts) ───────────────────────
    report_content = result.get("report_content", "").replace("\\n", "\n")
    if result.get("report_file_exists") and report_content.strip():
        report_upper = report_content.upper()
        is_report_recent = (start_time == 0 or result.get("report_mtime", 0) >= start_time)

        if is_report_recent:
            sections_found = 0
            for section in _REQUIRED_SECTIONS:
                if section in report_upper:
                    sections_found += 1

            pts_per_section = 25 // len(_REQUIRED_SECTIONS)  # 6 pts each
            section_score = sections_found * pts_per_section
            # Bonus for all 4 sections
            if sections_found == len(_REQUIRED_SECTIONS):
                section_score = 25

            score += section_score
            feedback_parts.append(
                f"{'PASS' if sections_found == 4 else 'PARTIAL'} "
                f"Report has {sections_found}/4 required sections (+{section_score})"
            )
        else:
            score += 3
            feedback_parts.append("PARTIAL Report exists but pre-dates task start (+3)")
    else:
        feedback_parts.append("FAIL Narrative report not written to /home/ga/Reports/timeline_report.txt")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
