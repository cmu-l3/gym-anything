#!/usr/bin/env python3
"""
Verifier for baseline_hash_elimination task.

Scoring (100 pts total, pass threshold = 70):
  10 pts - Autopsy case created and DB found
  10 pts - baseline_hashes.txt extracted correctly
  20 pts - Autopsy DB shows files successfully marked as 'Known' (known=1)
  10 pts - Suspect image ingested into Autopsy
  10 pts - Anomalous CSV file exists, is recent, and has pipe-delimited data rows
  25 pts - CSV output accurately contains anomalous files and filters out baseline files
  15 pts - Summary text file contains accurate counts
"""

import json
import os
import re
import tempfile

def verify_baseline_hash_elimination(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/baseline_task_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/baseline_gt.json")

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
        return {"passed": False, "score": 0, "feedback": "Result file not found. Export script may have failed."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # ── Pull ground truth ─────────────────────────────────────────────────────
    gt = {"baseline": {}, "anomalous": {}}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    gt_baseline_md5s = set(gt.get("baseline", {}).values())
    gt_anomalous_md5s = set(gt.get("anomalous", {}).values())
    gt_baseline_count = len(gt_baseline_md5s)
    gt_anomalous_count = len(gt_anomalous_md5s)

    # ── Criterion 1: Case DB found (10 pts) ───────────────────────────────────
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── Criterion 2: Baseline Hashes Extracted (10 pts) ───────────────────────
    start_time = result.get("start_time", 0)
    hash_content = result.get("baseline_hashes_content", "")
    
    # Extract MD5-looking strings
    found_hashes = set(re.findall(r'\b[a-fA-F0-9]{32}\b', hash_content))
    if len(found_hashes) >= gt_baseline_count * 0.8:
        score += 10
        feedback_parts.append(f"PASS Extracted {len(found_hashes)} hashes to baseline_hashes.txt (+10)")
    elif len(found_hashes) > 0:
        score += 5
        feedback_parts.append(f"PARTIAL Found {len(found_hashes)} hashes in baseline_hashes.txt (+5)")
    else:
        feedback_parts.append("FAIL baseline_hashes.txt missing or empty")

    # ── Criterion 3: Suspect Ingested (10 pts) ────────────────────────────────
    if result.get("suspect_added"):
        score += 10
        feedback_parts.append("PASS Suspect image added to case (+10)")
    else:
        feedback_parts.append("FAIL Suspect image not added")

    # ── Criterion 4: Autopsy Known Config (20 pts) ────────────────────────────
    known_files = result.get("db_known_files_count", 0)
    if known_files >= gt_baseline_count * 0.8:
        score += 20
        feedback_parts.append(f"PASS Autopsy successfully marked {known_files} files as Known (+20)")
    elif known_files > 0:
        score += 10
        feedback_parts.append(f"PARTIAL Autopsy marked {known_files} files as Known (+10)")
    else:
        feedback_parts.append("FAIL No files marked as Known in Autopsy DB (Hashset likely not configured correctly)")

    # ── Criterion 5: Anomalous CSV Format (10 pts) ────────────────────────────
    csv_exists = result.get("csv_exists", False)
    csv_mtime = result.get("csv_mtime", 0)
    csv_content = result.get("csv_content", "")
    
    lines = [l.strip() for l in csv_content.splitlines() if l.strip()]
    pipe_lines = [l for l in lines if '|' in l]
    has_header = any("FILENAME" in l.upper() for l in lines[:3])
    
    is_recent = start_time == 0 or csv_mtime >= start_time
    
    if csv_exists and is_recent and has_header and len(pipe_lines) > 1:
        score += 10
        feedback_parts.append("PASS CSV correctly formatted (+10)")
    elif csv_exists and len(pipe_lines) > 0:
        score += 5
        feedback_parts.append("PARTIAL CSV exists but missing header or stale (+5)")
    else:
        feedback_parts.append("FAIL anomalous_files.csv not found or invalid")

    # ── Criterion 6: Anomalous File Accuracy (25 pts) ─────────────────────────
    csv_md5s = set(re.findall(r'\b[a-f0-9]{32}\b', csv_content.lower()))
    
    tp = len(csv_md5s.intersection(gt_anomalous_md5s))
    fp = len(csv_md5s.intersection(gt_baseline_md5s))
    
    if gt_anomalous_count > 0:
        if tp >= gt_anomalous_count and fp == 0:
            score += 25
            feedback_parts.append(f"PASS Perfect anomalous isolation: {tp} found, 0 baseline files included (+25)")
        elif tp > 0:
            # Penalty for false positives (failing to eliminate baseline files)
            accuracy = (tp / gt_anomalous_count) * (1 - min(1, fp / max(1, gt_baseline_count)))
            awarded = int(25 * accuracy)
            score += awarded
            feedback_parts.append(f"PARTIAL Anomalous isolation accuracy: TP={tp}, FP={fp} (+{awarded})")
        else:
            feedback_parts.append("FAIL No correct anomalous files identified in CSV")
    else:
        feedback_parts.append("FAIL GT Anomalous count is 0 (Setup Error)")

    # ── Criterion 7: Summary Math/Counts (15 pts) ─────────────────────────────
    summary_content = result.get("summary_content", "").upper()
    summary_exists = result.get("summary_exists", False)
    
    if summary_exists:
        suspect_re = re.search(r'TOTAL_FILES_SUSPECT:\s*(\d+)', summary_content)
        elim_re = re.search(r'KNOWN_FILES_ELIMINATED:\s*(\d+)', summary_content)
        remain_re = re.search(r'ANOMALOUS_FILES_REMAINING:\s*(\d+)', summary_content)
        
        c_passed = 0
        if suspect_re and int(suspect_re.group(1)) >= (gt_baseline_count + gt_anomalous_count):
            c_passed += 5
        if elim_re and int(elim_re.group(1)) >= gt_baseline_count:
            c_passed += 5
        if remain_re and int(remain_re.group(1)) == tp:  # Should match what they reported
            c_passed += 5
            
        score += c_passed
        feedback_parts.append(f"INFO Summary counts parsed (+{c_passed})")
    else:
        feedback_parts.append("FAIL Summary file missing")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }