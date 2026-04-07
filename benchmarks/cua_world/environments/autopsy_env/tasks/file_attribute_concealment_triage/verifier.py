#!/usr/bin/env python3
"""
Verifier for file_attribute_concealment_triage task.

Scoring System (100 points, pass >= 60):
- Case DB & data source setup (10 pts)
- Ingest completed (5 pts)
- Selective extraction: All hidden files exported with NO false positives (30 pts)
- CSV Report: Properly formatted with accurate hidden file data (35 pts)
- Summary Report: Accurate counts and qualitative assessment (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_file_attribute_concealment_triage(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/concealment_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/concealment_gt.json")

    # 1. Pull Result JSON
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # 2. Pull GT JSON
    gt = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(gt_file_vm, tmp_path)
        with open(tmp_path) as f:
            gt = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        logger.warning(f"Could not read GT: {e}")

    # Use lowercase comparisons to avoid FAT 8.3 capitalization issues
    gt_hidden_names = set(n.lower() for n in gt.get("hidden_names", []))
    gt_normal_names = set(n.lower() for n in gt.get("normal_names", []))
    gt_total_hidden = gt.get("total_hidden", 0)
    gt_total_normal = gt.get("total_normal", 0)

    # ── Criterion 1: DB setup (10 pts) ──────────────────────────────────────────
    if result.get("case_db_found") and result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Case DB and data source found (+10)")
    else:
        feedback_parts.append("FAIL Case DB or data source missing")

    # ── Criterion 2: Ingest Completed (5 pts) ───────────────────────────────────
    if result.get("ingest_completed"):
        score += 5
        feedback_parts.append("PASS Ingest completed (+5)")
    else:
        feedback_parts.append("FAIL Ingest did not complete")

    # ── Criterion 3: Exported Files (30 pts) ────────────────────────────────────
    exported = result.get("exported_files", [])
    exported_names = [f["name"].lower() for f in exported]
    
    hidden_exported = sum(1 for n in exported_names if n in gt_hidden_names)
    normal_exported = sum(1 for n in exported_names if n in gt_normal_names)

    if gt_total_hidden > 0:
        if hidden_exported == gt_total_hidden and normal_exported == 0:
            score += 30
            feedback_parts.append(f"PASS Perfect extraction: all {hidden_exported} hidden files, 0 false positives (+30)")
        elif hidden_exported > 0:
            subscore = int((hidden_exported / gt_total_hidden) * 15)
            # Heavy penalty for false positives to discourage bulk-exporting everything
            penalty = normal_exported * 5
            awarded = max(0, subscore - penalty)
            score += awarded
            feedback_parts.append(f"PARTIAL Extracted {hidden_exported}/{gt_total_hidden} hidden files, {normal_exported} normal files (+{awarded})")
        else:
            if normal_exported > 0:
                feedback_parts.append(f"FAIL Extracted {normal_exported} normal files but NO hidden files")
            else:
                feedback_parts.append("FAIL No files exported to /home/ga/Reports/hidden_exports")
    else:
        feedback_parts.append("WARNING Ground truth has no hidden files!")

    # ── Criterion 4: CSV Report (35 pts) ────────────────────────────────────────
    csv_exists = result.get("csv_exists", False)
    csv_content = result.get("csv_content", "").replace("\\n", "\n")
    start_time = result.get("start_time", 0)
    csv_mtime = result.get("csv_mtime", 0)

    if csv_exists:
        if start_time == 0 or csv_mtime >= start_time:
            lines = [l.strip() for l in csv_content.splitlines() if l.strip()]
            has_header = any("FILENAME" in l.upper() and "HAS_HIDDEN_ATTR" in l.upper() for l in lines[:2])
            data_lines = [l for l in lines if "|" in l and "FILENAME" not in l.upper()]
            
            # Verify rows
            correct_rows = 0
            for line in data_lines:
                parts = line.split("|")
                if len(parts) >= 3:
                    fname = parts[0].strip().lower()
                    if fname in gt_hidden_names:
                        correct_rows += 1

            if has_header and correct_rows == gt_total_hidden and gt_total_hidden > 0:
                score += 35
                feedback_parts.append("PASS CSV report is perfectly formatted and contains all hidden files (+35)")
            elif has_header and correct_rows > 0:
                score += 20
                feedback_parts.append(f"PARTIAL CSV report has header and {correct_rows} valid hidden file rows (+20)")
            elif len(data_lines) > 0:
                score += 10
                feedback_parts.append("PARTIAL CSV report has data but lacks proper header or contains wrong files (+10)")
            else:
                score += 5
                feedback_parts.append("PARTIAL CSV report exists but has no valid data (+5)")
        else:
            feedback_parts.append("FAIL CSV report is stale (pre-dates task)")
    else:
        feedback_parts.append("FAIL CSV report not found")

    # ── Criterion 5: Summary Report (20 pts) ────────────────────────────────────
    summary_exists = result.get("summary_exists", False)
    summary_content = result.get("summary_content", "")

    if summary_exists:
        content_upper = summary_content.upper()
        
        has_hidden_count = str(gt_total_hidden) in content_upper and "HIDDEN" in content_upper
        has_normal_count = str(gt_total_normal) in content_upper and "NORMAL" in content_upper
        has_assessment = "ASSESSMENT" in content_upper

        if has_hidden_count and has_normal_count and has_assessment:
            score += 20
            feedback_parts.append("PASS Summary report has correct counts and assessment (+20)")
        elif has_hidden_count or has_normal_count:
            score += 10
            feedback_parts.append("PARTIAL Summary report has partial correct counts (+10)")
        else:
            score += 5
            feedback_parts.append("PARTIAL Summary report exists but lacks correct counts (+5)")
    else:
        feedback_parts.append("FAIL Summary report not found")

    # ── Pass condition ──────────────────────────────────────────────────────────
    # Task requires at least partial success on selective extraction and CSV creation
    key_criteria_met = (hidden_exported > 0) and csv_exists
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }