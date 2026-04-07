#!/usr/bin/env python3
"""
Verifier for obfuscated_fragment_reconstruction task.

Scoring (100 pts total, pass threshold = 65 AND successful hash match):
  10 pts  — Autopsy case created and DB found
  15 pts  — Disk image data source ingested
  15 pts  — Fragments tagged as Notable Items in Autopsy (proves GUI interaction)
  20 pts  — Reconstructed file exists and is > 0 bytes
  25 pts  — Reconstructed file MD5 perfectly matches ground truth (proves successful reconstruction)
  15 pts  — Forensic report exists with correct sequential order and MD5
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_obfuscated_fragment_reconstruction(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/obfuscated_fragment_result.json")
    correct_sequence = meta.get("correct_sequence", ["swap_frag.sys", "sys_cache.bin", "win_temp.dat"])

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ── Pull result JSON ──────────────────────────────────────────────────────
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file_vm, temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # ── Extract Data ──────────────────────────────────────────────────────────
    start_time = result.get("start_time", 0)
    gt_hash = result.get("gt_hash", "").lower()
    recon_md5 = result.get("reconstructed_md5", "").lower()
    
    # ── Criterion 1: Case DB Found (10 pts) ───────────────────────────────────
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found for Fragment_Recovery_2024 (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── Criterion 2: Data Source Added (15 pts) ───────────────────────────────
    if result.get("data_source_added"):
        score += 15
        feedback_parts.append("PASS Data source ingested (+15)")
    else:
        feedback_parts.append("FAIL Data source not found in DB")

    # ── Criterion 3: Fragments Tagged in Autopsy (15 pts) ─────────────────────
    tagged_count = result.get("db_tagged_items_count", 0)
    if tagged_count >= 3:
        score += 15
        feedback_parts.append(f"PASS {tagged_count} items tagged in Autopsy (+15)")
    elif tagged_count > 0:
        score += 5
        feedback_parts.append(f"PARTIAL Only {tagged_count}/3 items tagged in Autopsy (+5)")
    else:
        feedback_parts.append("FAIL No items tagged in Autopsy (GUI interaction missing)")

    # ── Criterion 4: Reconstructed File Exists (20 pts) ───────────────────────
    if result.get("reconstructed_file_exists"):
        recon_mtime = result.get("reconstructed_file_mtime", 0)
        recon_size = result.get("reconstructed_file_size", 0)
        
        if recon_size > 0 and (start_time == 0 or recon_mtime >= start_time):
            score += 20
            feedback_parts.append("PASS Reconstructed file created during session (+20)")
        elif recon_size > 0:
            score += 10
            feedback_parts.append("PARTIAL Reconstructed file exists but timestamps indicate stale data (+10)")
        else:
            feedback_parts.append("FAIL Reconstructed file is empty")
    else:
        feedback_parts.append("FAIL Reconstructed file not found at /home/ga/Reports/reconstructed_evidence.jpg")

    # ── Criterion 5: Cryptographic Match (25 pts) ─────────────────────────────
    # This is the most critical check—it guarantees they concatenated correctly.
    is_hash_match = False
    if gt_hash and recon_md5:
        if gt_hash == recon_md5:
            score += 25
            is_hash_match = True
            feedback_parts.append("PASS Reconstructed file MD5 matches ground truth exactly (+25)")
        else:
            feedback_parts.append(f"FAIL Reconstructed file MD5 ({recon_md5[:8]}...) does not match GT")
    else:
        feedback_parts.append("FAIL Missing MD5 hash for comparison")

    # ── Criterion 6: Forensic Report (15 pts) ─────────────────────────────────
    if result.get("report_exists"):
        report_content = result.get("report_content", "").lower()
        
        # Check if the correct sequence is mentioned in order
        sequence_regex = r".*swap_frag\.sys.*sys_cache\.bin.*win_temp\.dat.*"
        has_correct_order = bool(re.search(sequence_regex, report_content, re.DOTALL))
        
        # Check if MD5 is mentioned
        has_correct_md5 = False
        if gt_hash and gt_hash in report_content:
            has_correct_md5 = True
        
        if has_correct_order and has_correct_md5:
            score += 15
            feedback_parts.append("PASS Report contains correct sequence and accurate MD5 (+15)")
        elif has_correct_order or has_correct_md5:
            score += 7
            feedback_parts.append("PARTIAL Report exists but is missing either correct sequence or MD5 (+7)")
        else:
            feedback_parts.append("FAIL Report exists but lacks correct sequence and correct MD5")
    else:
        feedback_parts.append("FAIL Forensic report not found")

    # ── Final Evaluation ──────────────────────────────────────────────────────
    # They must hit the pass threshold AND successfully reconstruct the image
    passed = (score >= 65) and is_hash_match

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }