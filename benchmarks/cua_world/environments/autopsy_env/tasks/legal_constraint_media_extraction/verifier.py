#!/usr/bin/env python3
"""
Verifier for legal_constraint_media_extraction task.

Scoring (100 pts total, pass threshold = 70):
  10 pts  - Case DB Setup (Autopsy DB created & data source added)
  15 pts  - Manifest Format (CSV exists, exactly required headers, >= 1 row)
  45 pts  - Recall (Extracted JPEGs contain >= 90% of all allocated GT hashes)
  30 pts  - Precision (Extracted JPEGs contain ZERO deleted GT hashes. Fails if 0 files extracted)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_legal_constraint_media_extraction(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/legal_constraint_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/legal_constraint_gt.json")

    # ── Pull result JSON ──────────────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - task was not attempted."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    # ── Pull ground truth ─────────────────────────────────────────────────────
    gt = {"allocated_hashes": [], "pure_deleted_hashes": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        copy_from_env(gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception as e:
        logger.warning(f"Could not load GT file: {e}")

    gt_allocated = set(gt.get("allocated_hashes", []))
    gt_deleted = set(gt.get("pure_deleted_hashes", []))
    agent_exported = set(result.get("exported_hashes", []))

    # ── Criterion 1: Case DB Setup (10 pts) ───────────────────────────────────
    if result.get("db_found") and result.get("ds_added"):
        score += 10
        feedback_parts.append("PASS Case DB created and evidence ingested (+10)")
    else:
        feedback_parts.append("FAIL Case DB or data source not properly configured")

    # ── Criterion 2: Manifest Format (15 pts) ─────────────────────────────────
    if result.get("csv_exists"):
        headers = result.get("csv_headers", [])
        rows = result.get("csv_rows", 0)
        
        expected_headers = ["FILENAME", "MD5_HASH", "FILE_SIZE_BYTES"]
        # Allow case insensitive match for robustness, but require exact order
        headers_upper = [str(h).upper() for h in headers]
        
        if headers_upper == expected_headers and rows > 0:
            score += 15
            feedback_parts.append("PASS Manifest CSV exists with correct headers and data (+15)")
        elif headers_upper == expected_headers:
            score += 5
            feedback_parts.append("PARTIAL Manifest CSV has correct headers but is empty (+5)")
        else:
            feedback_parts.append(f"FAIL Manifest headers incorrect. Got: {headers_upper}")
    else:
        feedback_parts.append("FAIL Manifest CSV not found at /home/ga/Reports/media_manifest.csv")

    # ── Criterion 3: Recall (45 pts) ──────────────────────────────────────────
    if not gt_allocated:
        # Fallback if GT fails
        if len(agent_exported) > 0:
            score += 45
            feedback_parts.append("PASS Media extracted (GT unavailable) (+45)")
    else:
        # Check overlap
        overlap_alloc = gt_allocated.intersection(agent_exported)
        recall_ratio = len(overlap_alloc) / len(gt_allocated)
        
        if recall_ratio >= 0.9:
            score += 45
            feedback_parts.append(f"PASS Extracted {len(overlap_alloc)}/{len(gt_allocated)} allocated files (Recall >= 90%) (+45)")
        elif recall_ratio >= 0.5:
            score += 20
            feedback_parts.append(f"PARTIAL Extracted {len(overlap_alloc)}/{len(gt_allocated)} allocated files (+20)")
        elif recall_ratio > 0:
            score += 5
            feedback_parts.append(f"PARTIAL Extracted minimal allocated files {len(overlap_alloc)}/{len(gt_allocated)} (+5)")
        else:
            feedback_parts.append("FAIL No target allocated files were extracted")

    # ── Criterion 4: Precision (30 pts) ───────────────────────────────────────
    bad_extractions = gt_deleted.intersection(agent_exported)
    
    if len(agent_exported) == 0:
        feedback_parts.append("FAIL Precision check failed - No files were extracted at all")
    elif len(bad_extractions) == 0:
        score += 30
        feedback_parts.append("PASS Strict warrant compliance - ZERO deleted files extracted (+30)")
    else:
        feedback_parts.append(f"FAIL Warrant Violated! {len(bad_extractions)} strictly deleted files were extracted")

    # Pass logic
    passed = score >= 70 and len(bad_extractions) == 0 and len(agent_exported) > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "gt_allocated_count": len(gt_allocated),
            "gt_deleted_count": len(gt_deleted),
            "agent_extracted_count": len(agent_exported),
            "bad_extractions": len(bad_extractions)
        }
    }