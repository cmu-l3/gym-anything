#!/usr/bin/env python3
"""
Verifier for split_image_anti_forensics_reconstruction task.

Scoring (100 pts total, pass threshold = 60):
  20 pts  — Image properly reassembled (size & MD5 match GT).
  20 pts  — Autopsy case created and image ingested.
  20 pts  — Reconstruction log accurately populated.
  40 pts  — Hidden chunk CSV accurately identifies non-resident files in the chunk.
"""

import json
import os
import re
import tempfile


def verify_split_image_reconstruction(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    
    result_file_vm = meta.get("result_file", "/tmp/reconstruction_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/reconstruction_gt.json")

    # 1. Copy result JSON
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"](result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # 2. Copy GT JSON
    gt = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        return {"passed": False, "score": 0, "feedback": "Ground truth missing."}

    gt_md5 = gt.get("original_md5", "")
    gt_size = gt.get("original_size", 0)
    gt_inodes = set(str(i) for i in gt.get("hidden_inodes", []))

    # Criterion 1: Image Reassembly (20 pts)
    if result.get("restored_dd_exists"):
        agent_md5 = result.get("restored_dd_md5", "")
        agent_size = result.get("restored_dd_size", 0)
        
        if agent_md5 and gt_md5 and agent_md5.lower() == gt_md5.lower():
            score += 20
            feedback_parts.append("PASS Image accurately reconstructed (MD5 match) (+20)")
        elif agent_size == gt_size:
            score += 10
            feedback_parts.append("PARTIAL Image size matches, but MD5 differs (fragments out of order?) (+10)")
        else:
            feedback_parts.append("FAIL Reconstructed image size/MD5 does not match original")
    else:
        feedback_parts.append("FAIL restored.dd not found")

    # Criterion 2: Autopsy Case (20 pts)
    case_score = 0
    if result.get("case_db_found"):
        case_score += 10
        if result.get("data_source_added"):
            case_score += 5
        if result.get("ingest_completed"):
            case_score += 5
            
        score += case_score
        feedback_parts.append(f"PASS Autopsy Case setup/ingest successful (+{case_score})")
    else:
        feedback_parts.append("FAIL Autopsy case 'Fragment_Recovery_2024' not found")

    # Criterion 3: Log content (20 pts)
    log_content = result.get("log_content", "").upper()
    if result.get("log_exists"):
        log_pts = 0
        if "FRAG.001" in log_content and "SYSTEM_BACKUP.BAK" in log_content:
            log_pts += 5
        if str(gt_size) in log_content:
            log_pts += 5
        if gt_md5.upper() in log_content:
            log_pts += 5
        if "3072000" in log_content:
            log_pts += 5
            
        score += log_pts
        feedback_parts.append(f"LOG Checks: Awarded {log_pts}/20 points")
    else:
        feedback_parts.append("FAIL image_reconstruction_log.txt not found")

    # Criterion 4: Hidden Chunk CSV (40 pts)
    csv_content = result.get("csv_content", "").strip()
    if result.get("csv_exists") and csv_content:
        lines = [l for l in csv_content.splitlines() if '|' in l]
        agent_inodes = set()
        
        # Parse agent inodes
        for line in lines:
            parts = [p.strip() for p in line.split('|')]
            if len(parts) >= 2 and parts[1].isdigit():
                agent_inodes.add(parts[1])
                
        # Compare to GT
        if len(gt_inodes) == 0:
            if len(agent_inodes) == 0:
                score += 40
                feedback_parts.append("PASS Correctly identified 0 hidden files (+40)")
            else:
                feedback_parts.append("FAIL False positives in hidden files CSV")
        else:
            true_positives = len(agent_inodes.intersection(gt_inodes))
            false_positives = len(agent_inodes - gt_inodes)
            
            recall = true_positives / len(gt_inodes)
            precision = true_positives / max(1, len(agent_inodes))
            
            # Penalize heavily for false positives, reward for recall
            f1_score = 2 * (precision * recall) / max(0.01, (precision + recall))
            
            csv_pts = int(40 * f1_score)
            
            # Floor points if completely missed
            if true_positives == 0:
                csv_pts = 0
                
            score += csv_pts
            feedback_parts.append(f"CSV EVAL: Recall {true_positives}/{len(gt_inodes)}, FPs {false_positives} (+{csv_pts}/40)")
    else:
        feedback_parts.append("FAIL hidden_chunk_files.csv missing or empty")

    passed = score >= 60 and (result.get("restored_dd_exists") and result.get("csv_exists"))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }