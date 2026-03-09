#!/usr/bin/env python3
"""
Verifier for extract_http_objects task.

Criteria:
1. Extraction Quantity (20pts): Did the agent extract the correct number of files?
2. Extraction Integrity (30pts): Do the extracted files match ground truth (MD5)?
3. Anti-Gaming (10pts): Were files created *after* task start?
4. Report Existence (10pts): Does the report file exist?
5. Report Accuracy (15pts): Does report mention counts/filenames/hosts?
6. VLM Verification (15pts): Did agent verify work visually/use correct tools?
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_http_objects(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Unpack data
    agent_files = result.get("agent_files", {})
    gt_hashes = result.get("ground_truth_hashes", {})
    report_content = result.get("report_content", "")
    report_exists = result.get("report_exists", False)
    task_start = result.get("task_start_time", 0)
    expected_hosts = result.get("expected_hosts", "").split(',')
    
    score = 0
    feedback = []

    # --- Criterion 1 & 2: Extraction Quantity & Integrity (50 pts total) ---
    # We match agent files to ground truth files by MD5 hash
    
    matches = 0
    total_gt = len(gt_hashes)
    
    # Create reverse lookup for GT: hash -> filename
    gt_hash_map = {v: k for k, v in gt_hashes.items()}
    
    valid_agent_files = 0
    
    if total_gt == 0:
        feedback.append("Error: No ground truth files found (setup error?)")
    else:
        for fname, fmeta in agent_files.items():
            f_md5 = fmeta.get("md5")
            
            # Check content match
            if f_md5 in gt_hash_map:
                matches += 1
                valid_agent_files += 1
            else:
                # Maybe filename matches but content differs?
                if fname in gt_hashes:
                    feedback.append(f"File '{fname}' exists but content hash mismatch.")
                else:
                    feedback.append(f"Unknown file extracted: '{fname}'")

        # Score calculation
        # Integrity: (matches / total_gt) * 30
        integrity_score = (matches / total_gt) * 30 if total_gt > 0 else 0
        score += integrity_score
        
        # Quantity: If count matches, full points
        if len(agent_files) == total_gt:
            score += 20
            feedback.append(f"Correct file count extracted ({total_gt}).")
        elif len(agent_files) > 0:
            # Partial quantity points
            quant_score = (len(agent_files) / total_gt) * 20
            quant_score = min(20, quant_score) # Cap at 20
            score += quant_score
            feedback.append(f"Extracted {len(agent_files)}/{total_gt} files.")
        else:
            feedback.append("No files extracted.")

    # --- Criterion 3: Anti-Gaming / Timestamps (10 pts) ---
    timestamp_fail = False
    if valid_agent_files > 0:
        for fname, fmeta in agent_files.items():
            if fmeta.get("mtime", 0) < task_start:
                timestamp_fail = True
                break
        
        if not timestamp_fail:
            score += 10
            feedback.append("File timestamps valid.")
        else:
            feedback.append("Files have old timestamps (pre-task).")
    else:
        feedback.append("No files to check timestamps.")

    # --- Criterion 4: Report Existence (10 pts) ---
    if report_exists and len(report_content.strip()) > 10:
        score += 10
        feedback.append("Report file created.")
    else:
        feedback.append("Report file missing or empty.")

    # --- Criterion 5: Report Content (15 pts) ---
    # Check if report mentions the count and at least one host
    report_score = 0
    lower_report = report_content.lower()
    
    # Check count
    if str(total_gt) in lower_report:
        report_score += 5
    
    # Check filenames
    files_found = 0
    for fname in gt_hashes.keys():
        if fname.lower() in lower_report:
            files_found += 1
    
    if files_found > 0:
        report_score += 5
    
    # Check hosts
    host_found = False
    for host in expected_hosts:
        if host and host.lower() in lower_report:
            host_found = True
            break
    if host_found:
        report_score += 5
        
    score += report_score
    if report_score > 0:
        feedback.append(f"Report content analysis: {report_score}/15 pts.")

    # --- Criterion 6: VLM Verification (15 pts) ---
    # We want to verify they didn't just 'touch' files or do something weird.
    # Look for "Export Objects" dialog or tshark command.
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Review these screenshots of a user performing a Wireshark task.
        The user should be extracting HTTP objects.
        
        Look for either:
        1. The "Export - HTTP object list" window/dialog in Wireshark.
        2. A terminal window running a 'tshark' command.
        3. The user viewing the extracted files in a file manager.
        
        Return JSON:
        {
            "tool_used": "gui" or "cli" or "none",
            "evidence_found": true/false,
            "description": "what you see"
        }
        """
        
        vlm_resp = query_vlm(frames, prompt)
        vlm_parsed = vlm_resp.get("parsed", {})
        
        if vlm_parsed.get("evidence_found"):
            score += 15
            feedback.append("VLM confirmed tool usage.")
        else:
            feedback.append("VLM did not see explicit export actions (GUI or CLI).")
    else:
        feedback.append("No trajectory frames available for VLM.")

    # --- Final Verdict ---
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback),
        "details": {
            "gt_count": total_gt,
            "agent_count": len(agent_files),
            "matches": matches
        }
    }