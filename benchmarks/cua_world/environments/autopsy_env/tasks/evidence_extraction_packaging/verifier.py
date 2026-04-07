#!/usr/bin/env python3
"""
Verifier for evidence_extraction_packaging task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Autopsy case created and DB found
  10 pts  — Disk image data source added
  5 pts   — Ingest completed
  10 pts  — Extraction directory exists with >0 files
  10 pts  — Extracted file count within tolerance of GT
  15 pts  — Extracted files MD5 match ground truth MD5s
  10 pts  — Evidence manifest exists, is recent, has correct pipe-delimited format
  10 pts  — Manifest covers >= 50% of extracted GT filenames
  10 pts  — Manifest MD5 values match GT hashes for listed files
  10 pts  — Packaging summary has all required fields including correct image MD5
"""

import json
import os
import re
import tempfile

def verify_evidence_extraction(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/evidence_extraction_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/evidence_extraction_gt.json")

    # ── Pull result JSON ──────────────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env = env_info.get("copy_from_env")
        if not copy_from_env:
            return {"passed": False, "score": 0, "feedback": "Copy function unavailable."}
            
        copy_from_env(result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — task not attempted."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # ── Pull GT JSON ──────────────────────────────────────────────────────────
    gt = {"total_regular_files": 0, "md5_set": [], "image_md5": "", "files": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        copy_from_env(gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    gt_total = gt.get("total_regular_files", 0)
    gt_md5s = set(gt.get("md5_set", []))
    gt_sha256s = set(gt.get("sha256_set", []))
    gt_image_md5 = gt.get("image_md5", "")
    
    # Track criteria for passing
    has_files = False
    has_good_hashes = False

    # ── 1. Case DB (10 pts) ───────────────────────────────────────────────────
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── 2. Data source (10 pts) ───────────────────────────────────────────────
    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added (+10)")
    else:
        feedback_parts.append("FAIL Data source not found")

    # ── 3. Ingest (5 pts) ─────────────────────────────────────────────────────
    if result.get("ingest_completed"):
        score += 5
        feedback_parts.append("PASS Ingest completed (+5)")

    # ── 4 & 5. Extracted files existence and count (10 + 10 pts) ──────────────
    extracted_files = result.get("extracted_files", {})
    extracted_count = result.get("extracted_file_count", 0)
    
    if extracted_count > 0:
        score += 10
        has_files = True
        feedback_parts.append(f"PASS Extraction dir has {extracted_count} files (+10)")
        
        if gt_total > 0:
            if extracted_count >= gt_total * 0.8:
                score += 10
                feedback_parts.append(f"PASS Extracted count ({extracted_count}) >= 80% of GT ({gt_total}) (+10)")
            elif extracted_count >= gt_total * 0.5:
                score += 5
                feedback_parts.append(f"PARTIAL Extracted count ({extracted_count}) >= 50% of GT ({gt_total}) (+5)")
            else:
                feedback_parts.append(f"FAIL Extracted count ({extracted_count}) too low compared to GT ({gt_total})")
        else:
            score += 10
            feedback_parts.append("PASS Extracted files found (+10, no GT count available)")
    else:
        feedback_parts.append("FAIL Extraction directory empty or missing")

    # ── 6. Extracted files MD5 match GT (15 pts) ──────────────────────────────
    if extracted_count > 0 and gt_md5s:
        extracted_md5s = set(finfo.get("md5") for finfo in extracted_files.values() if finfo.get("md5"))
        matching_hashes = extracted_md5s.intersection(gt_md5s)
        
        if len(matching_hashes) >= gt_total * 0.5 or len(matching_hashes) >= extracted_count * 0.8:
            score += 15
            has_good_hashes = True
            feedback_parts.append(f"PASS Extracted file hashes match GT ({len(matching_hashes)} matches) (+15)")
        elif len(matching_hashes) > 0:
            score += 7
            has_good_hashes = True
            feedback_parts.append(f"PARTIAL Some extracted file hashes match GT ({len(matching_hashes)} matches) (+7)")
        else:
            feedback_parts.append("FAIL Extracted file hashes do not match GT hashes (wrong files extracted or corrupted)")
    elif extracted_count > 0:
        score += 15
        has_good_hashes = True
        feedback_parts.append("PASS Extracted files present (+15, no GT hashes available)")

    # ── 7 & 8 & 9. Manifest Verification (10 + 10 + 10 pts) ───────────────────
    start_time = result.get("start_time", 0)
    man_exists = result.get("manifest_exists")
    man_mtime = result.get("manifest_mtime", 0)
    man_content = result.get("manifest_content", "")
    
    if man_exists:
        is_recent = (start_time == 0 or man_mtime >= start_time)
        lines = [l.strip() for l in man_content.splitlines() if l.strip()]
        has_header = any("FILENAME" in l.upper() and "MD5" in l.upper() for l in lines[:3])
        pipe_lines = [l for l in lines if "|" in l and "FILENAME" not in l.upper()]
        
        # 7. Format
        if is_recent and has_header and len(pipe_lines) > 0:
            score += 10
            feedback_parts.append("PASS Manifest exists, is recent, and pipe-delimited (+10)")
        elif is_recent:
            score += 5
            feedback_parts.append("PARTIAL Manifest exists but format is imperfect (+5)")
            
        # 8 & 9. Content / Hashes
        if pipe_lines and gt_md5s:
            man_md5s = set()
            for l in pipe_lines:
                # Naively extract 32-char hex strings as MD5s
                matches = re.findall(r'\b[a-fA-F0-9]{32}\b', l)
                if matches:
                    man_md5s.update(m.lower() for m in matches)
                    
            valid_man_md5s = man_md5s.intersection(gt_md5s)
            
            if len(valid_man_md5s) >= gt_total * 0.5:
                score += 20  # Covers both criterion 8 and 9 fully
                feedback_parts.append(f"PASS Manifest contains valid GT hashes ({len(valid_man_md5s)} matches) (+20)")
            elif len(valid_man_md5s) > 0:
                score += 10
                feedback_parts.append(f"PARTIAL Manifest contains some valid GT hashes ({len(valid_man_md5s)} matches) (+10)")
            else:
                feedback_parts.append("FAIL Manifest does not contain valid matching GT hashes")
    else:
        feedback_parts.append("FAIL Manifest file missing or empty")

    # ── 10. Summary Verification (10 pts) ─────────────────────────────────────
    sum_exists = result.get("summary_exists")
    sum_mtime = result.get("summary_mtime", 0)
    sum_content = result.get("summary_content", "")
    
    if sum_exists:
        is_recent = (start_time == 0 or sum_mtime >= start_time)
        content_upper = sum_content.upper()
        
        has_case = "INV-EXT-007" in content_upper
        has_extracted = "TOTAL_FILES" in content_upper
        has_image_md5 = gt_image_md5.lower() in sum_content.lower() if gt_image_md5 else False
        
        if is_recent and has_case and has_extracted and (has_image_md5 or not gt_image_md5):
            score += 10
            feedback_parts.append("PASS Summary file has required fields and correct source image MD5 (+10)")
        elif is_recent and has_case:
            score += 5
            feedback_parts.append("PARTIAL Summary file exists but missing fields or correct image MD5 (+5)")
        else:
            feedback_parts.append("FAIL Summary file exists but missing crucial data or is stale")
    else:
        feedback_parts.append("FAIL Summary file missing")

    # Overall Pass requires case DB (10) + files extracted (10) + valid hashes (15) + >= 60 total
    passed = (score >= 60) and result.get("case_db_found", False) and has_files and has_good_hashes
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }