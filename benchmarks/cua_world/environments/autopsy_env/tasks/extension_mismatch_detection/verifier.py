#!/usr/bin/env python3
"""
Verifier for extension_mismatch_detection task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Case DB found and image ingested
  10 pts  — Disk image data source added to case
  10 pts  — Ingest completed with File Type Identification (MIME types detected)
  15 pts  — Extension mismatch artifacts (TSK_EXT_MISMATCH_DETECTED) found in Autopsy DB
  15 pts  — Mismatch catalog file exists, is recent, and has proper pipe-delimited header
  15 pts  — Mismatch catalog covers ≥50% of GT mismatched files
  15 pts  — Summary file exists with all 7 required section headers
  10 pts  — Mismatch count in summary is populated and within tolerance
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extension_mismatch_detection(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/extension_mismatch_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/extension_mismatch_gt.json")

    # ── Pull result JSON from VM ──────────────────────────────────────────────
    result = {}
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_file_vm, tmp_path)
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
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    # ── Pull Ground Truth from VM ─────────────────────────────────────────────
    gt = {"total_mismatches": 0, "mismatched_names": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        copy_from_env(gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass  # GT unavailable - degrade gracefully
        
    gt_names = set(n.lower() for n in gt.get("mismatched_names", []))
    gt_total = gt.get("total_mismatches", 0)

    # ── 1. Case DB & 2. Data Source (20 pts) ──────────────────────────────────
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

    # ── 3. MIME types (10 pts) ────────────────────────────────────────────────
    if result.get("db_has_mime_types") or result.get("ingest_completed"):
        score += 10
        feedback_parts.append("PASS File Type Identification completed (+10)")
    else:
        feedback_parts.append("FAIL MIME types missing in DB")

    # ── 4. Extension mismatch artifacts (15 pts) ──────────────────────────────
    db_mismatches = result.get("db_mismatch_artifact_count", 0)
    if db_mismatches > 0:
        score += 15
        feedback_parts.append(f"PASS Extension mismatch artifacts found in DB: {db_mismatches} (+15)")
    else:
        feedback_parts.append("FAIL No TSK_EXT_MISMATCH_DETECTED artifacts in DB")

    # ── 5. Catalog File Format (15 pts) ───────────────────────────────────────
    start_time = result.get("start_time", 0)
    cat_exists = result.get("catalog_file_exists", False)
    cat_mtime = result.get("catalog_mtime", 0)
    cat_content = result.get("catalog_content", "").replace("\\n", "\n").replace("\\t", "\t")
    
    cat_lines = [l.strip() for l in cat_content.splitlines() if l.strip()]
    data_lines = []
    has_header = False

    if cat_exists:
        if start_time == 0 or cat_mtime >= start_time:
            # Check for header
            if len(cat_lines) > 0 and "FILENAME" in cat_lines[0].upper() and "|" in cat_lines[0]:
                has_header = True
                data_lines = cat_lines[1:]
            else:
                data_lines = cat_lines
                
            pipe_delimited = [l for l in data_lines if "|" in l and len(l.split("|")) >= 3]
            
            if has_header and len(pipe_delimited) > 0:
                score += 15
                feedback_parts.append(f"PASS Catalog has valid header and {len(pipe_delimited)} pipe-delimited rows (+15)")
            elif len(pipe_delimited) > 0:
                score += 8
                feedback_parts.append(f"PARTIAL Catalog has {len(pipe_delimited)} rows but missing strict header (+8)")
            else:
                score += 4
                feedback_parts.append("PARTIAL Catalog exists but lacks pipe-delimited format (+4)")
        else:
            feedback_parts.append("FAIL Catalog exists but predates task start (stale)")
    else:
        feedback_parts.append("FAIL Catalog file missing")

    # ── 6. GT Overlap in Catalog (15 pts) ─────────────────────────────────────
    if len(data_lines) > 0 and gt_total > 0:
        cat_lower = cat_content.lower()
        matched = sum(1 for name in gt_names if name in cat_lower)
        coverage = matched / len(gt_names)
        
        if coverage >= 0.5:
            score += 15
            feedback_parts.append(f"PASS Catalog covers {matched}/{gt_total} GT files ({coverage:.0%}) (+15)")
        elif coverage > 0:
            score += 7
            feedback_parts.append(f"PARTIAL Catalog covers {matched}/{gt_total} GT files ({coverage:.0%}) (+7)")
        else:
            feedback_parts.append("FAIL Catalog does not contain expected GT mismatched files")
    elif len(data_lines) > 0 and gt_total == 0:
        # If GT couldn't compute but agent found things
        score += 15
        feedback_parts.append("PASS Catalog has content (GT unverified) (+15)")
    else:
        feedback_parts.append("FAIL No recognizable data in Catalog to compare with GT")

    # ── 7. Summary File Format (15 pts) ───────────────────────────────────────
    sum_exists = result.get("summary_file_exists", False)
    sum_mtime = result.get("summary_mtime", 0)
    sum_content = result.get("summary_content", "").replace("\\n", "\n")
    
    required_keys = [
        "CASE_NAME", "CASE_NUMBER", "IMAGE_ANALYZED", "TOTAL_FILES_SCANNED",
        "TOTAL_MISMATCHES_DETECTED", "MISMATCH_CATEGORIES", "CONCEALMENT_ASSESSMENT"
    ]
    
    sum_upper = sum_content.upper()
    keys_found = sum(1 for k in required_keys if k in sum_upper)
    
    if sum_exists:
        if start_time == 0 or sum_mtime >= start_time:
            if keys_found == len(required_keys):
                score += 15
                feedback_parts.append("PASS Summary file contains all required sections (+15)")
            elif keys_found >= 4:
                score += 8
                feedback_parts.append(f"PARTIAL Summary missing some sections ({keys_found}/{len(required_keys)} found) (+8)")
            else:
                score += 4
                feedback_parts.append(f"PARTIAL Summary exists but lacks required structure (+4)")
        else:
            feedback_parts.append("FAIL Summary file exists but predates task start (stale)")
    else:
        feedback_parts.append("FAIL Summary file missing")

    # ── 8. Mismatch Count Tolerance (10 pts) ──────────────────────────────────
    if sum_exists:
        m = re.search(r'TOTAL_MISMATCHES_DETECTED:\s*(\d+)', sum_content, re.IGNORECASE)
        if m:
            reported_count = int(m.group(1))
            if gt_total > 0:
                # ± 30% tolerance or ± 2 absolute
                if reported_count == gt_total or abs(reported_count - gt_total) <= max(2, gt_total * 0.3):
                    score += 10
                    feedback_parts.append(f"PASS Reported mismatches ({reported_count}) within tolerance of GT ({gt_total}) (+10)")
                else:
                    feedback_parts.append(f"FAIL Reported mismatches ({reported_count}) out of tolerance vs GT ({gt_total})")
            else:
                score += 10
                feedback_parts.append(f"PASS Reported mismatches extracted: {reported_count} (GT unverified) (+10)")
        else:
            feedback_parts.append("FAIL Could not extract TOTAL_MISMATCHES_DETECTED number from summary")
    else:
        feedback_parts.append("FAIL Summary missing, cannot extract totals")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }