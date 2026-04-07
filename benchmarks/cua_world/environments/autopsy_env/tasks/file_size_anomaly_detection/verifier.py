#!/usr/bin/env python3
"""
Verifier for file_size_anomaly_detection task.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_file_size_anomaly_detection(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/size_anomaly_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/size_anomaly_gt.json")

    # --- Pull Result JSON ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"](result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    # --- Pull Ground Truth JSON ---
    gt = {"total_files": 0, "file_names": [], "ratio": 0.0}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    gt_names = set(n.lower() for n in gt.get("file_names", []))
    gt_total = gt.get("total_files", 0)
    start_time = result.get("start_time", 0)

    # 1. DB & DS added (10 + 10 = 20 pts)
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added (+10)")
    else:
        feedback_parts.append("FAIL Data source not added")

    # 2. Ingest Completed (10 pts)
    if result.get("ingest_completed"):
        score += 10
        feedback_parts.append("PASS Ingest completed (+10)")
    else:
        feedback_parts.append("FAIL Ingest incomplete")

    # 3. Inventory CSV format & size (10 + 15 = 25 pts)
    csv_exists = result.get("inventory_exists", False)
    csv_mtime = result.get("inventory_mtime", 0)
    csv_content = result.get("inventory_content", "").replace("\\n", "\n").replace("\\t", "\t")
    
    csv_lines = [l.strip() for l in csv_content.splitlines() if l.strip()]
    data_lines = [l for l in csv_lines if "|" in l and "FILENAME" not in l.upper()]

    if csv_exists and (start_time == 0 or csv_mtime >= start_time):
        has_header = any("FILENAME" in l.upper() for l in csv_lines[:3])
        if has_header and len(data_lines) > 0:
            score += 10
            feedback_parts.append("PASS Inventory CSV well-formatted and recent (+10)")
            
            # File count matching
            if gt_total > 0 and abs(len(data_lines) - gt_total) <= 3:
                score += 15
                feedback_parts.append(f"PASS Inventory rows ({len(data_lines)}) matches GT ({gt_total}) (+15)")
            elif gt_total > 0 and len(data_lines) >= gt_total // 2:
                score += 7
                feedback_parts.append(f"PARTIAL Inventory rows ({len(data_lines)}) partially matches GT ({gt_total}) (+7)")
            else:
                feedback_parts.append(f"FAIL Inventory rows mismatch. Expected ~{gt_total}, got {len(data_lines)}")
        else:
            feedback_parts.append("FAIL Inventory CSV missing header or empty")
    else:
        feedback_parts.append("FAIL Inventory CSV missing or stale")

    # 4. Inventory Coverage (10 pts)
    if data_lines and gt_names:
        csv_lower = csv_content.lower()
        matched = sum(1 for n in gt_names if n in csv_lower)
        coverage = matched / len(gt_names) if len(gt_names) > 0 else 0
        if coverage >= 0.5:
            score += 10
            feedback_parts.append(f"PASS Inventory covers {coverage*100:.0f}% of actual files (+10)")
        else:
            feedback_parts.append(f"FAIL Inventory coverage too low ({coverage*100:.0f}%)")

    # 5. Anomaly Report (35 pts total)
    rep_exists = result.get("report_exists", False)
    rep_mtime = result.get("report_mtime", 0)
    rep_content = result.get("report_content", "").replace("\\n", "\n")

    if rep_exists and (start_time == 0 or rep_mtime >= start_time):
        score += 10
        feedback_parts.append("PASS Analytical report exists and is recent (+10)")

        # Parsing report for checks
        total_m = re.search(r'TOTAL_FILES:\s*(\d+)', rep_content, re.IGNORECASE)
        alloc_m = re.search(r'ALLOCATED_FILES:\s*(\d+)', rep_content, re.IGNORECASE)
        del_m = re.search(r'DELETED_FILES:\s*(\d+)', rep_content, re.IGNORECASE)
        ratio_m = re.search(r'DELETED_TO_ALLOCATED_RATIO:\s*([\d.]+)', rep_content, re.IGNORECASE)
        
        # Internal consistency (5 pts)
        if total_m and alloc_m and del_m:
            if int(total_m.group(1)) == int(alloc_m.group(1)) + int(del_m.group(1)):
                score += 5
                feedback_parts.append("PASS Report counts internally consistent (+5)")
            else:
                feedback_parts.append("FAIL Report TOTAL_FILES != ALLOCATED + DELETED")
        else:
            feedback_parts.append("FAIL Missing count sections in report")

        # Size brackets sum correctly (5 pts)
        bracket_sum = 0
        b_matches = re.finditer(r'(?:0 bytes|1-1023 bytes|1KB-99KB|100KB-999KB|1MB\+):\s*(\d+)\s*files?', rep_content, re.IGNORECASE)
        b_count = 0
        for b in b_matches:
            bracket_sum += int(b.group(1))
            b_count += 1
            
        if b_count >= 5 and total_m and bracket_sum == int(total_m.group(1)):
            score += 5
            feedback_parts.append("PASS Size brackets sum matches TOTAL_FILES (+5)")
        else:
            feedback_parts.append(f"FAIL Size brackets sum ({bracket_sum}) does not match expected format/TOTAL_FILES")

        # Ratio accuracy (10 pts)
        gt_ratio = gt.get("ratio", 0.0)
        if ratio_m:
            try:
                rep_ratio = float(ratio_m.group(1))
                if abs(rep_ratio - gt_ratio) <= 0.5:
                    score += 10
                    feedback_parts.append(f"PASS Ratio ({rep_ratio}) within tolerance of GT ({gt_ratio}) (+10)")
                else:
                    feedback_parts.append(f"FAIL Ratio ({rep_ratio}) differs from GT ({gt_ratio})")
            except ValueError:
                feedback_parts.append("FAIL Invalid ratio format")
        else:
            feedback_parts.append("FAIL Missing DELETED_TO_ALLOCATED_RATIO section")

        # Conclusion check (5 pts)
        concl_m = re.search(r'CONCLUSION:\s*(.{10,})', rep_content, re.IGNORECASE | re.DOTALL)
        if concl_m:
            score += 5
            feedback_parts.append("PASS Conclusion section present (+5)")
        else:
            feedback_parts.append("FAIL Conclusion section missing or too short")
            
    else:
        feedback_parts.append("FAIL Analytical report missing or stale")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }