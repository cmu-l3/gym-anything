#!/usr/bin/env python3
"""
Verifier for forensic_report_generation task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Autopsy case created and DB found matching required name
  15 pts  — Disk image data source added to case
  10 pts  — Ingest completed (files indexed in DB)
  20 pts  — HTML report exists in case directory and was generated during task
  15 pts  — HTML report contains substantive content (references to the evidence)
  10 pts  — Case summary memo exists and was written during the task
  15 pts  — Memo contains all 8 required fields, formatted correctly
  5 pts   — Memo's TOTAL_FILES_ANALYZED is plausible and REPORT_LOCATION is accurate
"""

import json
import os
import re
import tempfile


def verify_forensic_report_generation(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/forensic_report_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/forensic_report_gt.json")

    # ── 1. Pull result JSON from VM ──────────────────────────────────────────
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

    # ── 2. Pull GT JSON from VM ──────────────────────────────────────────────
    gt = {"total_files": 0, "allocated_files": 0, "deleted_files": 0}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass
        
    gt_total_files = gt.get("total_files", 0)

    # ── Criterion 1: Case DB (10 pts) ─────────────────────────────────────────
    if result.get("case_db_found") and result.get("case_name_matches"):
        score += 10
        feedback_parts.append("PASS Case DB found for DA_Report_Case_2024 (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found — case was not created")

    # ── Criterion 2: Data Source (15 pts) ─────────────────────────────────────
    if result.get("data_source_added"):
        score += 15
        feedback_parts.append("PASS Data source added to case (+15)")
    else:
        feedback_parts.append("FAIL Data source not found in case DB")

    # ── Criterion 3: Ingest Completed (10 pts) ────────────────────────────────
    if result.get("ingest_completed"):
        score += 10
        feedback_parts.append("PASS Ingest completed (+10)")
    else:
        feedback_parts.append("FAIL Ingest did not complete")

    # ── Criterion 4 & 5: HTML Report Exists & Substantive (35 pts) ────────────
    html_reports = result.get("html_reports", [])
    start_time = result.get("start_time", 0)
    
    valid_html_reports = [r for r in html_reports if start_time == 0 or r["mtime"] >= start_time]
    
    best_html_report_dir = ""
    if valid_html_reports:
        score += 20
        feedback_parts.append(f"PASS HTML report generated during task (+20)")
        
        # Check substance: Should be > 1KB and mention data source or case
        substantive = False
        for r in valid_html_reports:
            content_lower = r.get("content_sample", "").lower()
            if r.get("size", 0) > 1024 and ("ntfs_undel" in content_lower or "da_report_case" in content_lower or "autopsy" in content_lower):
                substantive = True
                best_html_report_dir = r.get("dir", "")
                break
                
        if substantive:
            score += 15
            feedback_parts.append("PASS HTML report contains substantive content (+15)")
        else:
            feedback_parts.append("FAIL HTML report lacks expected substantive content")
    else:
        feedback_parts.append("FAIL No recent HTML report found in the case Reports directory")

    # ── Criterion 6 & 7: Memo Exists & Fields (25 pts) ────────────────────────
    memo_exists = result.get("memo_exists", False)
    memo_mtime = result.get("memo_mtime", 0)
    memo_content = result.get("memo_content", "").strip()
    
    memo_fields_extracted = {}
    
    if memo_exists:
        if start_time == 0 or memo_mtime >= start_time:
            score += 10
            feedback_parts.append("PASS Case summary memo exists and is recent (+10)")
            
            # Extract fields
            for line in memo_content.splitlines():
                if ":" in line:
                    parts = line.split(":", 1)
                    key = parts[0].strip().upper()
                    val = parts[1].strip()
                    memo_fields_extracted[key] = val
            
            required_keys = [
                "CASE_NAME", "CASE_NUMBER", "DATA_SOURCE", "REPORT_FORMAT", 
                "REPORT_LOCATION", "TOTAL_FILES_ANALYZED", "INGEST_MODULES_RUN", "ANALYSIS_COMPLETE"
            ]
            
            missing_keys = [k for k in required_keys if k not in memo_fields_extracted or not memo_fields_extracted[k]]
            
            if not missing_keys:
                score += 15
                feedback_parts.append("PASS Memo contains all required fields (+15)")
            else:
                points_per_key = 15 / len(required_keys)
                found_keys_count = len(required_keys) - len(missing_keys)
                partial_score = int(found_keys_count * points_per_key)
                score += partial_score
                feedback_parts.append(f"PARTIAL Memo missing {len(missing_keys)} fields ({partial_score}/15)")
                
        else:
            feedback_parts.append("FAIL Memo file exists but is stale (created before task start)")
    else:
        feedback_parts.append("FAIL Case summary memo not found at /home/ga/Reports/case_summary_memo.txt")

    # ── Criterion 8: Memo Plausibility & Accuracy (5 pts) ─────────────────────
    if memo_exists and "TOTAL_FILES_ANALYZED" in memo_fields_extracted and "REPORT_LOCATION" in memo_fields_extracted:
        files_str = memo_fields_extracted["TOTAL_FILES_ANALYZED"]
        files_num = 0
        
        # Extract number from string
        num_match = re.search(r'\d+', files_str.replace(',', ''))
        if num_match:
            files_num = int(num_match.group(0))
            
        location_str = memo_fields_extracted["REPORT_LOCATION"]
        
        # Plausibility check: GT total is usually between 500-1500 for this image. 
        # Give generous bounds (-80% to +200%) to account for Autopsy differences vs TSK.
        plausible_files = gt_total_files == 0 or (files_num > gt_total_files * 0.2 and files_num < gt_total_files * 3.0)
        
        # Location check: Should point to the directory where we found the HTML
        accurate_location = False
        if best_html_report_dir and best_html_report_dir.strip('/').lower() in location_str.strip('/').lower().replace('\\', '/'):
            accurate_location = True
            
        if plausible_files and accurate_location:
            score += 5
            feedback_parts.append("PASS Memo metrics and report location are accurate (+5)")
        else:
            if not plausible_files:
                feedback_parts.append(f"FAIL Memo files analyzed ({files_num}) not plausible (GT: ~{gt_total_files})")
            if not accurate_location:
                feedback_parts.append("FAIL Memo REPORT_LOCATION does not match actual HTML output directory")
    
    # Check pass threshold
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }