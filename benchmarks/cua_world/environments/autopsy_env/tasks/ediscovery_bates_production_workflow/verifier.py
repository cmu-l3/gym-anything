#!/usr/bin/env python3
"""
Verifier for ediscovery_bates_production_workflow task.

Scoring (100 pts total, pass threshold = 70):
  10 pts  - Case Database Exists
  10 pts  - Data Source Ingested
  20 pts  - Bates Directory Populated (files sequentially named PROD-XXXX.txt)
  20 pts  - Load File Format (pipe delimited, correct headers)
  20 pts  - Accurate Hashes/Sizes (load file matches actual files)
  20 pts  - Ground Truth Coverage (Extracted files map to ≥90% of actual image .txt files)
"""

import json
import os
import tempfile

def verify_ediscovery_bates(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ── Pull result JSON ──────────────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"]("/tmp/ediscovery_result.json", tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # ── Pull ground truth JSON ─────────────────────────────────────────────────
    gt = {"txt_hashes": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"]("/tmp/ediscovery_gt.json", tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    # 1. DB (10 pts)
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # 2. Data source (10 pts)
    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added (+10)")
    else:
        feedback_parts.append("FAIL Data source not added")

    # 3. Bates Dir Populated (20 pts)
    bates_files = result.get("bates_files", {})
    prod_files = [fn for fn in bates_files.keys() if fn.startswith("PROD-")]
    if len(prod_files) > 0:
        score += 20
        feedback_parts.append(f"PASS Bates directory populated with {len(prod_files)} PROD files (+20)")
    else:
        feedback_parts.append("FAIL Bates directory not populated correctly")

    # 4. Load File Format (20 pts)
    lf_content = result.get("load_file_content", "")
    lines = [l.strip() for l in lf_content.splitlines() if l.strip()]
    valid_format = False
    parsed_entries = []
    
    if len(lines) > 0:
        header = lines[0]
        if "BATES_NUMBER" in header and "ORIGINAL_FILENAME" in header and "MD5_HASH" in header and "FILE_SIZE" in header and "|" in header:
            valid_format = True
            headers = header.split("|")
            for line in lines[1:]:
                parts = line.split("|")
                if len(parts) == len(headers):
                    parsed_entries.append(dict(zip(headers, parts)))
                    
            if len(parsed_entries) > 0:
                score += 20
                feedback_parts.append("PASS Load file format correct and contains data rows (+20)")
            else:
                score += 10
                feedback_parts.append("PARTIAL Load file has correct header but no data (+10)")
        else:
            feedback_parts.append("FAIL Load file has incorrect header/delimiter")
    else:
        feedback_parts.append("FAIL Load file missing or empty")

    # 5. Accurate Hashes/Sizes (20 pts)
    accurate_entries = 0
    if valid_format and len(parsed_entries) > 0 and len(prod_files) > 0:
        for entry in parsed_entries:
            bates_num = entry.get("BATES_NUMBER", "").strip()
            fn_with_ext = bates_num if bates_num.endswith(".txt") else f"{bates_num}.txt"
            expected_md5 = entry.get("MD5_HASH", "").strip().lower()
            expected_size = str(entry.get("FILE_SIZE", "")).strip()
            
            if fn_with_ext in bates_files:
                actual = bates_files[fn_with_ext]
                if actual["md5"] == expected_md5 and str(actual["size"]) == expected_size:
                    accurate_entries += 1
                    
        if accurate_entries == len(parsed_entries) and accurate_entries == len(prod_files):
            score += 20
            feedback_parts.append("PASS Hashes and sizes in CSV identically match the files (+20)")
        elif accurate_entries > 0:
            score += 10
            feedback_parts.append(f"PARTIAL {accurate_entries} entries accurately match (+10)")
        else:
            feedback_parts.append("FAIL Hashes/sizes do not match actual files")
    else:
        feedback_parts.append("FAIL Cannot verify hash accuracy (missing files or invalid load file)")

    # 6. Ground Truth Coverage (20 pts)
    gt_hashes = set(gt.get("txt_hashes", []))
    bates_hashes = set([v["md5"] for v in bates_files.values()])
    coverage = 0
    
    if len(gt_hashes) > 0:
        coverage = len(gt_hashes.intersection(bates_hashes)) / len(gt_hashes)
        if coverage >= 0.9:
            score += 20
            feedback_parts.append(f"PASS Extracted files account for {coverage*100:.0f}% of actual .txt files (+20)")
        elif coverage > 0.4:
            score += 10
            feedback_parts.append(f"PARTIAL Extracted files account for {coverage*100:.0f}% of actual .txt files (+10)")
        else:
            feedback_parts.append(f"FAIL Insufficient GT coverage ({coverage*100:.0f}%)")
    else:
        if len(bates_hashes) == 0:
            score += 20
            coverage = 1.0
            feedback_parts.append("PASS No .txt files in GT and none extracted (+20)")
        else:
            feedback_parts.append("FAIL GT has no txt files but agent extracted some")

    # Final pass threshold (70 points) and strict core criteria check
    passed = score >= 70 and valid_format and coverage >= 0.9

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }