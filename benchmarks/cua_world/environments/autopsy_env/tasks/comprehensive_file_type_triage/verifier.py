#!/usr/bin/env python3
"""
Verifier for comprehensive_file_type_triage task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  - Case DB found for USB_Triage_2024
  10 pts  - Disk image added as data source
  10 pts  - File Type Identification ran (MIME types populated in DB)
  10 pts  - DB file count matches GT closely
  10 pts  - Inventory file exists and is recent
  10 pts  - Inventory has required category headers
  15 pts  - Inventory file names cover >=60% of GT file names
  10 pts  - Summary file exists and has all required fields
  10 pts  - Summary counts (total, deleted) within +/-20% of GT
   5 pts  - Internal consistency (category sum approx equals total files)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_comprehensive_file_type_triage(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/file_type_triage_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/file_type_triage_gt.json")

    # 1. Pull Result JSON
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"](result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - task was not attempted."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    # 2. Pull GT JSON
    gt = {"total_files": 0, "deleted_count": 0, "file_names": []}
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
    gt_deleted = gt.get("deleted_count", 0)
    gt_names = set([n.lower() for n in gt.get("file_names", [])])

    # --- Criterion 1: Case DB found (10 pts) ---
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # --- Criterion 2: Data source added (10 pts) ---
    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added (+10)")
    else:
        feedback_parts.append("FAIL Data source not found in DB")

    # --- Criterion 3: MIME types populated (10 pts) ---
    files_with_mime = result.get("db_files_with_mime", 0)
    if files_with_mime > 0:
        score += 10
        feedback_parts.append(f"PASS MIME types populated for {files_with_mime} files (+10)")
    else:
        feedback_parts.append("FAIL MIME types not populated (File Type Identification did not run)")

    # --- Criterion 4: File count accuracy (10 pts) ---
    db_total = result.get("db_total_files", 0)
    if gt_total > 0 and abs(db_total - gt_total) / gt_total <= 0.2:
        score += 10
        feedback_parts.append("PASS DB file count accurate (+10)")
    elif db_total > 0:
        score += 5
        feedback_parts.append("PARTIAL DB file count partially accurate (+5)")
    else:
        feedback_parts.append("FAIL DB file count is zero")

    # --- Criterion 5: Inventory exists & recent (10 pts) ---
    inv_content = result.get("inventory_content", "").replace("\\n", "\n")
    start_time = result.get("start_time", 0)
    inv_mtime = result.get("inventory_mtime", 0)
    
    if result.get("inventory_file_exists") and (start_time == 0 or inv_mtime >= start_time):
        score += 10
        feedback_parts.append("PASS Inventory file exists and is recent (+10)")
    else:
        feedback_parts.append("FAIL Inventory file missing or stale")

    # --- Criterion 6: Inventory headers (10 pts) ---
    required_headers = ["=== IMAGES ===", "=== DOCUMENTS ===", "=== EXECUTABLES ===", "=== ARCHIVES ===", "=== OTHER ==="]
    headers_found = [h for h in required_headers if h in inv_content]
    if len(headers_found) == 5:
        score += 10
        feedback_parts.append("PASS Inventory has all 5 required headers (+10)")
    elif len(headers_found) > 0:
        score += len(headers_found) * 2
        feedback_parts.append(f"PARTIAL Inventory has {len(headers_found)}/5 headers (+{len(headers_found) * 2})")
    else:
        feedback_parts.append("FAIL Inventory missing required headers")

    # --- Criterion 7: Inventory coverage (15 pts) ---
    if inv_content.strip() and gt_names:
        inv_lower = inv_content.lower()
        matched = sum(1 for name in gt_names if name in inv_lower)
        coverage = matched / len(gt_names) if gt_names else 0
        if coverage >= 0.6:
            score += 15
            feedback_parts.append(f"PASS Inventory covers {coverage:.0%} of GT files (+15)")
        elif coverage >= 0.3:
            score += 7
            feedback_parts.append(f"PARTIAL Inventory covers {coverage:.0%} of GT files (+7)")
        else:
            feedback_parts.append(f"FAIL Inventory covers only {coverage:.0%} of GT files")

    # --- Criterion 8: Summary fields (10 pts) ---
    sum_content = result.get("summary_content", "").replace("\\n", "\n").upper()
    req_fields = [
        "CASE_NAME", "CASE_NUMBER", "DATA_SOURCE", "TOTAL_FILES", "TOTAL_DIRECTORIES",
        "ALLOCATED_FILES", "DELETED_FILES", "CATEGORY_IMAGES", "CATEGORY_DOCUMENTS",
        "CATEGORY_EXECUTABLES", "CATEGORY_ARCHIVES", "CATEGORY_OTHER", "LARGEST_FILE", "RECOMMENDATION"
    ]
    fields_found = [f for f in req_fields if f in sum_content]
    if len(fields_found) == len(req_fields):
        score += 10
        feedback_parts.append("PASS Summary file has all required fields (+10)")
    elif len(fields_found) >= 7:
        score += 5
        feedback_parts.append(f"PARTIAL Summary has {len(fields_found)}/{len(req_fields)} fields (+5)")
    else:
        feedback_parts.append(f"FAIL Summary missing most fields ({len(fields_found)}/{len(req_fields)})")

    # --- Criterion 9: Summary counts accuracy (10 pts) ---
    total_val = None
    del_val = None
    for line in sum_content.splitlines():
        if "TOTAL_FILES" in line:
            m = re.search(r'\d+', line)
            if m: total_val = int(m.group())
        if "DELETED_FILES" in line:
            m = re.search(r'\d+', line)
            if m: del_val = int(m.group())
            
    if total_val is not None and gt_total > 0 and abs(total_val - gt_total) / gt_total <= 0.2:
        score += 5
        feedback_parts.append("PASS Summary total_files count accurate (+5)")
    if del_val is not None and gt_deleted > 0 and abs(del_val - gt_deleted) / gt_deleted <= 0.2:
        score += 5
        feedback_parts.append("PASS Summary deleted_files count accurate (+5)")

    # --- Criterion 10: Internal consistency (5 pts) ---
    cat_sum = 0
    for line in sum_content.splitlines():
        if line.startswith("CATEGORY_"):
            m = re.search(r'\d+', line)
            if m: cat_sum += int(m.group())
            
    if total_val is not None and cat_sum > 0 and abs(cat_sum - total_val) / max(1, total_val) <= 0.15:
        score += 5
        feedback_parts.append("PASS Summary category counts are internally consistent (+5)")

    # Key criteria: Case created and at least one report file generated
    key_criteria_met = result.get("case_db_found") and (result.get("inventory_file_exists") or result.get("summary_file_exists"))
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }