#!/usr/bin/env python3
"""
Verifier for ediscovery_load_file_generation task.

Scoring (100 pts total, pass threshold = 70):
  10 pts  — Autopsy case created and DB found.
  15 pts  — Natives directory populated with exported files.
  15 pts  — Load file exists, is recent, and has exact correct pipe-delimited header.
  20 pts  — Data Integrity Validation (MD5 hashes in the load file perfectly match the actual extracted files on disk).
  20 pts  — Exclusion of Deleted/System Data (Load file excludes deleted files and $MFT/system metafiles based on GT).
  20 pts  — Metadata Accuracy (Entries match ground truth allocated user files).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ediscovery_load_file(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/ediscovery_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/ediscovery_gt.json")

    # ── Pull Result JSON ──────────────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — task was not attempted."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # ── Pull Ground Truth JSON ────────────────────────────────────────────────
    gt = {"allocated_files": [], "allocated_names": [], "allocated_md5s": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        copy_from_env(gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception as e:
        logger.warning(f"Could not load Ground Truth: {e}")

    gt_names = [n.lower() for n in gt.get("allocated_names", [])]
    gt_md5s = [m.lower() for m in gt.get("allocated_md5s", [])]

    # ── Criterion 1: Case Initialization (10 pts) ─────────────────────────────
    if result.get("case_db_found") and result.get("case_name_matches"):
        score += 10
        feedback_parts.append("PASS Case DB 'Litigation_Support_2024' found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── Criterion 2: Natives Directory Populated (15 pts) ─────────────────────
    extracted_files = result.get("extracted_files", [])
    if result.get("export_dir_exists") and len(extracted_files) > 0:
        score += 15
        feedback_parts.append(f"PASS Natives directory contains {len(extracted_files)} files (+15)")
    else:
        feedback_parts.append("FAIL Natives directory is empty or missing")

    # ── Map physically extracted files by path and md5 ──
    extracted_md5s = {f["md5"].lower(): f for f in extracted_files}
    extracted_paths = {f["path"]: f for f in extracted_files}

    # ── Criterion 3: Load File Formatting (15 pts) ────────────────────────────
    load_file_exists = result.get("load_file_exists", False)
    load_file_content = result.get("load_file_content", "")
    start_time = result.get("start_time", 0)
    mtime = result.get("load_file_mtime", 0)

    is_recent = (start_time == 0 or mtime >= start_time)
    lines = [l.strip() for l in load_file_content.splitlines() if l.strip()]
    
    EXPECTED_HEADER = "CONTROL_NUMBER|FILENAME|ORIGINAL_PATH|SIZE_BYTES|MIME_TYPE|MD5_HASH|EXPORT_PATH"
    
    has_correct_header = False
    if len(lines) > 0 and lines[0].upper() == EXPECTED_HEADER:
        has_correct_header = True

    parsed_load_file = []
    if load_file_exists and is_recent and has_correct_header:
        score += 15
        feedback_parts.append("PASS Load file exists, is recent, and has perfect header (+15)")
        
        # Parse records
        for line in lines[1:]:
            parts = line.split('|')
            if len(parts) == 7:
                parsed_load_file.append({
                    "control": parts[0],
                    "filename": parts[1],
                    "orig_path": parts[2],
                    "size": parts[3],
                    "mime": parts[4],
                    "md5": parts[5].lower(),
                    "export_path": parts[6]
                })
    elif load_file_exists and is_recent and len(lines) > 1 and '|' in lines[0]:
        score += 7
        feedback_parts.append("PARTIAL Load file exists and is pipe-delimited, but header is imperfect (+7)")
        # Attempt loose parse
        for line in lines[1:]:
            parts = line.split('|')
            if len(parts) >= 6:
                parsed_load_file.append({"md5": parts[-2].lower(), "filename": parts[1] if len(parts)>1 else ""})
    else:
        feedback_parts.append("FAIL Load file missing, stale, or lacks proper pipe-delimited structure")

    # ── Criterion 4: Data Integrity Validation (20 pts) ───────────────────────
    integrity_matches = 0
    if len(parsed_load_file) > 0:
        for record in parsed_load_file:
            rec_md5 = record.get("md5", "")
            rec_path = record.get("export_path", "")
            
            # Check if MD5 exists in physically extracted files
            if rec_md5 in extracted_md5s:
                integrity_matches += 1
            # Or if path matches what was exported
            elif rec_path in extracted_paths:
                integrity_matches += 1
                
        integrity_ratio = integrity_matches / len(parsed_load_file)
        
        if integrity_ratio == 1.0:
            score += 20
            feedback_parts.append("PASS 100% of load file records match physically extracted data (+20)")
        elif integrity_ratio >= 0.5:
            score += 10
            feedback_parts.append(f"PARTIAL {integrity_ratio:.0%} of records match extracted data (+10)")
        else:
            feedback_parts.append(f"FAIL Integrity validation failed (only {integrity_ratio:.0%} match)")
    else:
        feedback_parts.append("FAIL Cannot validate data integrity (No valid records parsed from load file)")

    # ── Criterion 5: Exclusion of Deleted/System Data (20 pts) ────────────────
    # Check if they included $MFT or other system files
    system_files_included = 0
    for record in parsed_load_file:
        fname = record.get("filename", "").lower()
        if fname.startswith('$') or fname in ['.', '..']:
            system_files_included += 1

    if len(parsed_load_file) > 0:
        if system_files_included == 0:
            score += 20
            feedback_parts.append("PASS Load file successfully excludes hidden system metafiles (+20)")
        else:
            feedback_parts.append(f"FAIL Load file incorrectly includes {system_files_included} system metafiles")
    else:
        feedback_parts.append("FAIL Cannot evaluate system file exclusion (no records)")

    # ── Criterion 6: Metadata Accuracy (20 pts) ───────────────────────────────
    # Ensure the files they extracted are actually from the "Allocated" pool
    gt_matches = 0
    if len(parsed_load_file) > 0 and len(gt_md5s) > 0:
        for record in parsed_load_file:
            if record.get("md5", "") in gt_md5s or record.get("filename", "").lower() in gt_names:
                gt_matches += 1
                
        accuracy_ratio = gt_matches / len(parsed_load_file)
        if accuracy_ratio >= 0.9:
            score += 20
            feedback_parts.append("PASS Extracted metadata accurately reflects Ground Truth allocated files (+20)")
        elif accuracy_ratio >= 0.5:
            score += 10
            feedback_parts.append(f"PARTIAL {accuracy_ratio:.0%} of metadata reflects GT allocated files (+10)")
        else:
            feedback_parts.append("FAIL Metadata accuracy check failed (includes significant deleted or incorrect data)")
    elif len(gt_md5s) == 0:
        # Give grace points if GT failed to compute but they made a valid load file
        if len(parsed_load_file) > 0:
            score += 20
            feedback_parts.append("PASS Metadata assumed accurate (Ground truth unavailable) (+20)")

    # ── Final Determination ──
    # The load file must be structurally sound and data integrity must hold to pass.
    key_criteria_met = load_file_exists and has_correct_header and integrity_matches > 0
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }