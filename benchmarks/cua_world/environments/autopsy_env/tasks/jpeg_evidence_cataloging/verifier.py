#!/usr/bin/env python3
"""
Verifier for jpeg_evidence_cataloging task.

Scoring (100 pts total, pass threshold = 70):
  15 pts  — Autopsy case created and DB found
  15 pts  — Disk image data source added
  10 pts  — Ingest completed with MIME-type identification
  20 pts  — JPEG files cataloged in DB (count matches GT within tolerance)
  20 pts  — Catalog TSV file exists, is recent, and has correct format
  20 pts  — Catalog covers ≥50% of GT JPEG file names
"""

import json
import os
import re
import tempfile


def verify_jpeg_evidence_cataloging(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/jpeg_evidence_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/jpeg_evidence_gt.json")

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
            "feedback": "Result file not found — task was not attempted or export did not run."
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # ── Pull ground truth ──────────────────────────────────────────────────────
    gt = {"total_jpegs": 0, "allocated_count": 0, "deleted_count": 0, "jpeg_names": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    gt_total = gt.get("total_jpegs", 0)
    gt_names = set(n.lower() for n in gt.get("jpeg_names", []))

    # ── Criterion 1: Case DB found (15 pts) ───────────────────────────────────
    if result.get("case_db_found") and result.get("case_name_matches"):
        score += 15
        feedback_parts.append("PASS Case DB found for JPEG_Catalog_2024 (+15)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── Criterion 2: Data source added (15 pts) ───────────────────────────────
    if result.get("data_source_added"):
        score += 15
        feedback_parts.append("PASS Data source added (+15)")
    else:
        feedback_parts.append("FAIL Data source not found in DB")

    # ── Criterion 3: Ingest with MIME types (10 pts) ──────────────────────────
    if result.get("ingest_completed") or result.get("db_has_mime_types"):
        score += 10
        feedback_parts.append("PASS Ingest completed with file type identification (+10)")
    else:
        feedback_parts.append("FAIL Ingest did not complete or MIME types not populated")

    # ── Criterion 4: JPEG count in DB (20 pts) ────────────────────────────────
    db_count = result.get("db_jpeg_count", 0)
    if gt_total > 0:
        if db_count >= gt_total - 1:
            score += 20
            feedback_parts.append(f"PASS DB JPEG count {db_count} matches GT {gt_total} (+20)")
        elif db_count >= max(1, gt_total // 2):
            score += 10
            feedback_parts.append(f"PARTIAL DB JPEG count {db_count}/{gt_total} (+10)")
        else:
            feedback_parts.append(f"FAIL DB JPEG count {db_count}, expected ~{gt_total}")
    else:
        if db_count >= 1:
            score += 15
            feedback_parts.append(f"PASS {db_count} JPEGs found in DB (+15, no GT)")
        else:
            feedback_parts.append("FAIL No JPEG files found in DB")

    # ── Criterion 5: Catalog TSV format (20 pts) ──────────────────────────────
    start_time = result.get("start_time", 0)
    catalog_mtime = result.get("catalog_mtime", 0)
    catalog_content = result.get("catalog_content", "").replace("\\n", "\n").replace("\\t", "\t")

    if result.get("catalog_file_exists"):
        if start_time == 0 or catalog_mtime >= start_time:
            # Check TSV format: has tabs, has header with FILENAME
            lines = [l for l in catalog_content.splitlines() if l.strip()]
            has_header = any("FILENAME" in l.upper() for l in lines[:3])
            has_tabs = any("\t" in l for l in lines)
            data_lines = len([l for l in lines if "\t" in l and "FILENAME" not in l.upper()])

            if has_header and has_tabs and data_lines >= 1:
                score += 20
                feedback_parts.append(
                    f"PASS Catalog TSV has header and {data_lines} data rows (+20)"
                )
            elif has_tabs or data_lines >= 1:
                score += 10
                feedback_parts.append(
                    f"PARTIAL Catalog TSV has data but may lack proper header (+10)"
                )
            else:
                score += 5
                feedback_parts.append("PARTIAL Catalog file exists but format incorrect (+5)")
        else:
            score += 5
            feedback_parts.append("PARTIAL Catalog file exists but pre-dates task start (+5)")
    else:
        feedback_parts.append("FAIL Catalog TSV not written to /home/ga/Reports/jpeg_catalog.tsv")

    # ── Criterion 6: Catalog covers GT JPEG names (20 pts) ────────────────────
    if catalog_content.strip() and gt_names:
        catalog_lower = catalog_content.lower()
        matched = sum(1 for name in gt_names if name in catalog_lower)
        coverage = matched / len(gt_names) if gt_names else 0

        if coverage >= 0.8:
            score += 20
            feedback_parts.append(
                f"PASS Catalog covers {matched}/{len(gt_names)} GT JPEG names ({coverage:.0%}) (+20)"
            )
        elif coverage >= 0.5:
            score += 12
            feedback_parts.append(
                f"PARTIAL Catalog covers {matched}/{len(gt_names)} GT names ({coverage:.0%}) (+12)"
            )
        elif coverage >= 0.25:
            score += 5
            feedback_parts.append(
                f"PARTIAL Catalog covers {matched}/{len(gt_names)} GT names ({coverage:.0%}) (+5)"
            )
        else:
            feedback_parts.append(
                f"FAIL Catalog covers only {matched}/{len(gt_names)} GT names"
            )
    elif catalog_content.strip() and not gt_names:
        # GT unavailable
        lines = [l for l in catalog_content.splitlines() if "\t" in l and "FILENAME" not in l.upper()]
        if lines:
            score += 15
            feedback_parts.append(f"PASS Catalog has {len(lines)} data rows (GT unavailable, +15)")
        else:
            score += 3
            feedback_parts.append("PARTIAL Catalog exists but GT unavailable for name check (+3)")
    else:
        feedback_parts.append("FAIL Catalog is empty or not written")

    # ── Summary file feedback ──────────────────────────────────────────────────
    summary_content = result.get("summary_content", "").replace("\\n", "\n")
    if result.get("summary_file_exists") and summary_content.strip():
        feedback_parts.append("INFO Summary file present")
    else:
        feedback_parts.append("INFO Summary file not found at /home/ga/Reports/jpeg_catalog_summary.txt")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
