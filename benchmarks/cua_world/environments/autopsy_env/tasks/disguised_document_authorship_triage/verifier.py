#!/usr/bin/env python3
"""
Verifier for disguised_document_authorship_triage task.

Multi-Criteria Scoring (100 pts total, pass threshold = 70):
  15 pts - Autopsy case created and DB populated (Anti-gaming: ensuring Autopsy was used)
  15 pts - File Type ID module ran (Anti-gaming: checking if MIME types were assigned in DB)
  10 pts - Report file exists, is recent, and has correct basic sections
  20 pts - Report claims exactly the correct number of target documents
  15 pts - True MIME types (html/rtf) correctly identified in the report lines
  25 pts - Hashes match targets exactly (strict penalty for false positives)
  
Additionally performs a VLM check using trajectory frames to ensure the UI was interacted with.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_disguised_document_authorship(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}

    # 1. Pull Result JSON
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/authorship_triage_result.json", tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # 2. Pull Ground Truth
    gt = {"target_files": [], "decoy_files": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        copy_from_env("/tmp/authorship_gt.json", tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    target_hashes = set(f["md5"] for f in gt.get("target_files", []))
    target_count_expected = len(gt.get("target_files", []))

    # Criterion 1: DB & Autopsy Execution (Anti-gaming)
    if result.get("case_db_found") and result.get("data_source_added"):
        score += 15
        feedback_parts.append("PASS Case DB and data source created (+15)")
    else:
        feedback_parts.append("FAIL Case DB missing or logical files not added")

    # Criterion 2: File Type ID Ran (Anti-gaming)
    if result.get("file_type_id_ran"):
        score += 15
        feedback_parts.append("PASS File Type Identification ran and populated MIME types (+15)")
    else:
        feedback_parts.append("FAIL File Type Identification did not populate MIME types in DB")

    # Criterion 3: Report Validation
    report_content = result.get("report_content", "").replace("\\n", "\n")
    if result.get("report_exists"):
        is_recent = result.get("report_mtime", 0) >= result.get("start_time", 0)
        
        has_header1 = "CASE_NUMBER" in report_content
        has_header2 = "TARGET_DOCUMENTS:" in report_content

        if is_recent and has_header1 and has_header2:
            score += 10
            feedback_parts.append("PASS Report exists, is recent, and has basic format (+10)")
        else:
            feedback_parts.append("PARTIAL Report exists but format is incorrect or stale")
            
        # Criterion 4: Document Count Claim
        doc_count_match = re.search(r"DOCUMENTS_BY_TARGET:\s*(\d+)", report_content)
        if doc_count_match:
            claimed_count = int(doc_count_match.group(1))
            if claimed_count == target_count_expected:
                score += 20
                feedback_parts.append(f"PASS Claimed exact target count: {claimed_count} (+20)")
            else:
                feedback_parts.append(f"FAIL Claimed count {claimed_count} does not match expected {target_count_expected}")
        else:
            feedback_parts.append("FAIL DOCUMENTS_BY_TARGET field missing or invalid")

        # Parse the pipe-delimited records
        lines = [l.strip() for l in report_content.splitlines() if l.strip()]
        pipe_lines = [l for l in lines if "|" in l and "TARGET_DOCUMENTS" not in l]
        
        reported_hashes = set()
        correct_mime_types = 0
        
        for pline in pipe_lines:
            parts = pline.split("|")
            if len(parts) >= 4:
                mime_type = parts[1].strip().lower()
                md5_hash = parts[3].strip().lower()
                reported_hashes.add(md5_hash)
                
                # Check MIME type correctness
                if "html" in mime_type or "rtf" in mime_type:
                    correct_mime_types += 1
                    
        # Criterion 5: True File Types Identified
        if correct_mime_types > 0:
            if correct_mime_types >= target_count_expected:
                score += 15
                feedback_parts.append("PASS True MIME types (html/rtf) correctly identified (+15)")
            else:
                score += 7
                feedback_parts.append("PARTIAL True MIME types partially identified (+7)")
        else:
            feedback_parts.append("FAIL True MIME types were not correctly documented in report")

        # Criterion 6: Hash Accuracy (Strict check)
        valid_matches = reported_hashes.intersection(target_hashes)
        false_positives = reported_hashes - target_hashes
        
        if len(valid_matches) == target_count_expected and len(false_positives) == 0:
            score += 25
            feedback_parts.append("PASS Found exact target documents with no false positives (+25)")
        elif len(valid_matches) > 0:
            penalty = len(false_positives) * 5
            awarded = max(0, (len(valid_matches) * (25 // target_count_expected)) - penalty)
            score += awarded
            feedback_parts.append(f"PARTIAL Found {len(valid_matches)} targets, {len(false_positives)} false positives (+{awarded})")
        else:
            feedback_parts.append("FAIL No correct target document hashes found in report")
            
    else:
        feedback_parts.append("FAIL Report file authorship_attribution.txt not found")

    # 7. VLM Verification (Trajectory checking)
    try:
        # Import dynamically to fail gracefully if unavailable in test environment
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        from gym_anything.utils import query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        if frames and final:
            prompt = """
            Look at these screenshots of an agent performing digital forensics in Autopsy.
            Did the agent actively interact with the Autopsy UI to examine file metadata, text contents, or use the keyword search features?
            Respond strictly in JSON format:
            {
                "used_autopsy_ui": true/false
            }
            """
            vlm_response = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_response.get("success"):
                if not vlm_response.get("parsed", {}).get("used_autopsy_ui", True):
                    score = max(0, score - 30)
                    feedback_parts.append("VLM PENALTY: Autopsy UI interaction not detected (-30)")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    key_criteria_met = score >= 70
    passed = key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }