#!/usr/bin/env python3
"""
Verifier for allocation_delta_correlation_analysis task.

Scoring (100 pts total, pass threshold = 60):
  15 pts - Mount & Inventory: `mounted_txt_files.txt` exists and line count matches GT allocated `.txt` count.
   5 pts - Hygiene: Image is unmounted at the end.
  15 pts - Autopsy Case: Case created and data source added.
  15 pts - Report Format: the key-value pairs are properly parsed from the report.
  15 pts - Allocation Accuracy: `MOUNTED_TXT_COUNT` matches GT allocated count.
  15 pts - Autopsy Yield Accuracy: `AUTOPSY_TXT_COUNT` matches GT total count.
  20 pts - Delta Calculation: `DELETED_TXT_DELTA` matches GT deleted count, and `DELTA_FILENAMES` has correct files.
"""

import json
import os
import re
import tempfile


def verify_allocation_delta_correlation(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/delta_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/delta_gt.json")

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
            "feedback": "Result file not found — task was not attempted."
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # ── Pull ground truth from VM ─────────────────────────────────────────────
    gt = {
        "allocated_txt_count": 0,
        "deleted_txt_count": 0,
        "total_txt_count": 0,
        "deleted_txt_names": []
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

    gt_allocated = gt.get("allocated_txt_count", 0)
    gt_total = gt.get("total_txt_count", 0)
    gt_deleted = gt.get("deleted_txt_count", 0)
    gt_deleted_names = set(n.lower() for n in gt.get("deleted_txt_names", []))

    start_time = result.get("start_time", 0)

    # ── Criterion 1: Mount & Inventory (15 pts) ───────────────────────────────
    if result.get("mounted_report_exists"):
        mtime = result.get("mounted_report_mtime", 0)
        lines = result.get("mounted_report_lines", 0)
        
        if (start_time == 0 or mtime >= start_time):
            if lines == gt_allocated:
                score += 15
                feedback_parts.append(f"PASS Native mount inventory correctly found {lines} allocated files (+15)")
            elif lines > 0:
                score += 7
                feedback_parts.append(f"PARTIAL Native mount inventory found {lines} files, expected {gt_allocated} (+7)")
            else:
                feedback_parts.append("FAIL Native mount inventory exists but is empty")
        else:
            feedback_parts.append("FAIL Native mount inventory pre-dates task start (stale)")
    else:
        feedback_parts.append("FAIL /home/ga/Reports/mounted_txt_files.txt not found")

    # ── Criterion 2: Hygiene (5 pts) ──────────────────────────────────────────
    if result.get("is_unmounted"):
        score += 5
        feedback_parts.append("PASS Loopback image cleanly unmounted (+5)")
    else:
        feedback_parts.append("FAIL Loopback image was left mounted")

    # ── Criterion 3: Autopsy Case Creation (15 pts) ───────────────────────────
    if result.get("case_db_found") and result.get("data_source_added"):
        score += 15
        feedback_parts.append("PASS Autopsy case created and data source ingested (+15)")
    elif result.get("case_db_found"):
        score += 5
        feedback_parts.append("PARTIAL Autopsy case created but data source missing (+5)")
    else:
        feedback_parts.append("FAIL Autopsy case not found")

    # ── Analyze Delta Report ──────────────────────────────────────────────────
    delta_content = result.get("delta_report_content", "")
    has_format = False
    
    parsed_mounted = -1
    parsed_autopsy = -1
    parsed_delta = -1
    parsed_filenames = []

    if result.get("delta_report_exists"):
        mtime = result.get("delta_report_mtime", 0)
        if start_time == 0 or mtime >= start_time:
            # Try to parse the report
            m1 = re.search(r"MOUNTED_TXT_COUNT:\s*(\d+)", delta_content)
            m2 = re.search(r"AUTOPSY_TXT_COUNT:\s*(\d+)", delta_content)
            m3 = re.search(r"DELETED_TXT_DELTA:\s*(\d+)", delta_content)
            
            if m1: parsed_mounted = int(m1.group(1))
            if m2: parsed_autopsy = int(m2.group(1))
            if m3: parsed_delta = int(m3.group(1))
            
            # Find filenames listed under DELTA_FILENAMES
            # Look for lines starting with hyphen after DELTA_FILENAMES section
            if "DELTA_FILENAMES:" in delta_content:
                files_section = delta_content.split("DELTA_FILENAMES:")[1]
                parsed_filenames = re.findall(r"^\s*-\s*\[?(.*?\.txt)\]?", files_section, re.IGNORECASE | re.MULTILINE)
            
            if m1 and m2 and m3:
                has_format = True

    # ── Criterion 4: Report Format (15 pts) ───────────────────────────────────
    if has_format:
        score += 15
        feedback_parts.append("PASS Delta report followed requested structural format (+15)")
    elif result.get("delta_report_exists"):
        score += 5
        feedback_parts.append("PARTIAL Delta report exists but lacks required structure (+5)")
    else:
        feedback_parts.append("FAIL Delta report not found")

    # ── Criterion 5: Allocation Accuracy (15 pts) ─────────────────────────────
    if has_format:
        if parsed_mounted == gt_allocated:
            score += 15
            feedback_parts.append(f"PASS Reported native count ({parsed_mounted}) matches GT (+15)")
        else:
            feedback_parts.append(f"FAIL Reported native count ({parsed_mounted}) incorrect, expected {gt_allocated}")

    # ── Criterion 6: Autopsy Yield Accuracy (15 pts) ──────────────────────────
    if has_format:
        if parsed_autopsy == gt_total:
            score += 15
            feedback_parts.append(f"PASS Reported Autopsy count ({parsed_autopsy}) matches GT (+15)")
        else:
            feedback_parts.append(f"FAIL Reported Autopsy count ({parsed_autopsy}) incorrect, expected {gt_total}")

    # ── Criterion 7: Delta Calculation (20 pts) ───────────────────────────────
    if has_format:
        delta_correct = (parsed_delta == gt_deleted)
        
        # Check if the listed filenames are actually the deleted ones
        names_lower = [n.strip().lower() for n in parsed_filenames]
        matched_names = sum(1 for n in names_lower if n in gt_deleted_names)
        
        # If there are deleted files, require at least some match
        if gt_deleted > 0:
            if delta_correct and matched_names >= gt_deleted:
                score += 20
                feedback_parts.append("PASS Delta math is correct and filenames match deleted GT files (+20)")
            elif delta_correct and matched_names > 0:
                score += 10
                feedback_parts.append(f"PARTIAL Delta math correct, but only {matched_names}/{gt_deleted} filenames correct (+10)")
            elif delta_correct:
                score += 5
                feedback_parts.append("PARTIAL Delta math correct, but filenames missing or wrong (+5)")
            else:
                feedback_parts.append(f"FAIL Delta math incorrect ({parsed_delta} vs {gt_deleted})")
        else:
            # If no deleted files exist (GT = 0), then delta should be 0 and list should be empty
            if delta_correct and len(parsed_filenames) == 0:
                score += 20
                feedback_parts.append("PASS Delta math is correct (0 files) (+20)")
            elif delta_correct:
                score += 10
                feedback_parts.append("PARTIAL Delta math is correct (0) but files erroneously listed (+10)")
            else:
                feedback_parts.append(f"FAIL Delta math incorrect ({parsed_delta} vs 0)")

    passed = score >= 60 and result.get("delta_report_exists") and has_format

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }