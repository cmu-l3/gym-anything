#!/usr/bin/env python3
"""
Verifier for NTFS ADS Concealment Detection task.

Checks:
1. Initialization: Autopsy DB created OR Sleuth Kit CLI tools used (10 pts)
2. Summary report exists and indicates 3 ADS found (10 pts)
3. CSV Report formatted correctly (Header present, pipe-delimited) (20 pts)
4. Extracted Parent Filenames are correct (20 pts)
5. Extracted Stream Names are correct (20 pts)
6. Extracted Content is correct (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ntfs_ads_concealment(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract metadata for ground truth
    metadata = task_info.get('metadata', {})
    expected_findings = metadata.get('expected_findings', [])
    expected_total_ads = metadata.get('expected_total_ads', 3)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/ads_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}. The export script may not have run."
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    start_time = result.get("start_time", 0)

    # 1. Initialization (10 pts)
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("Init: Autopsy Case DB found (+10)")
    elif result.get("tsk_cli_used"):
        score += 10
        feedback_parts.append("Init: Sleuth Kit CLI commands found (+10)")
    else:
        feedback_parts.append("Init: No evidence of Autopsy case or CLI usage (0)")

    # 2. Summary Report (10 pts)
    if result.get("summary_exists"):
        mtime = result.get("summary_mtime", 0)
        if start_time > 0 and mtime < start_time:
            feedback_parts.append("Summary: File predates task start (0)")
        else:
            summary_content = result.get("summary_content", "").upper()
            if f"TOTAL_ADS_FOUND: {expected_total_ads}" in summary_content or f"TOTAL_ADS_FOUND:3" in summary_content.replace(" ", ""):
                score += 10
                feedback_parts.append("Summary: Correctly reported 3 ADS (+10)")
            else:
                feedback_parts.append("Summary: Incorrect ADS count reported (0)")
    else:
        feedback_parts.append("Summary: Report missing (0)")

    # 3. CSV formatting and extraction (remaining 80 pts)
    parents_found = set()
    streams_found = set()
    contents_found = set()
    
    csv_valid_lines = 0
    
    if result.get("csv_exists"):
        mtime = result.get("csv_mtime", 0)
        if start_time > 0 and mtime < start_time:
            feedback_parts.append("CSV: File predates task start (0)")
        else:
            csv_content = result.get("csv_content", "")
            lines = [line.strip() for line in csv_content.splitlines() if line.strip()]
            
            # Check for header
            has_header = False
            if lines and "PARENT_FILENAME" in lines[0].upper():
                has_header = True
                lines = lines[1:] # strip header
            
            if has_header:
                score += 10
                feedback_parts.append("CSV Format: Header found (+10)")
            
            # Parse lines
            for line in lines:
                parts = [p.strip() for p in line.split("|")]
                if len(parts) >= 3:
                    csv_valid_lines += 1
                    parents_found.add(parts[0].lower())
                    streams_found.add(parts[1].lower())
                    contents_found.add(parts[2].lower())
            
            if csv_valid_lines >= 3:
                score += 10
                feedback_parts.append("CSV Format: Valid pipe-delimited lines found (+10)")
            elif csv_valid_lines > 0:
                score += 5
                feedback_parts.append("CSV Format: Some pipe-delimited lines found (+5)")
            else:
                feedback_parts.append("CSV Format: No valid pipe-delimited lines found (0)")
    else:
        feedback_parts.append("CSV: Report missing (0)")

    # Scoring the actual extracted data
    expected_parents = {f["parent"].lower() for f in expected_findings}
    expected_streams = {f["stream"].lower() for f in expected_findings}
    expected_contents = {f["content"].lower() for f in expected_findings}

    # Match parents (20 pts)
    matched_parents = parents_found.intersection(expected_parents)
    if len(matched_parents) == 3:
        score += 20
        feedback_parts.append("Parents: All expected parent files identified (+20)")
    elif len(matched_parents) > 0:
        pts = int(20 * (len(matched_parents) / 3))
        score += pts
        feedback_parts.append(f"Parents: {len(matched_parents)}/3 parent files identified (+{pts})")

    # Match streams (20 pts)
    matched_streams = streams_found.intersection(expected_streams)
    if len(matched_streams) == 3:
        score += 20
        feedback_parts.append("Streams: All expected stream names identified (+20)")
    elif len(matched_streams) > 0:
        pts = int(20 * (len(matched_streams) / 3))
        score += pts
        feedback_parts.append(f"Streams: {len(matched_streams)}/3 stream names identified (+{pts})")

    # Match contents (20 pts)
    matched_contents = 0
    for found_c in contents_found:
        # Allow partial matches as the agent might truncate or format slightly differently
        for exp_c in expected_contents:
            if exp_c in found_c or found_c in exp_c:
                matched_contents += 1
                expected_contents.remove(exp_c)
                break
                
    if matched_contents == 3:
        score += 20
        feedback_parts.append("Content: All stream contents extracted correctly (+20)")
    elif matched_contents > 0:
        pts = int(20 * (matched_contents / 3))
        score += pts
        feedback_parts.append(f"Content: {matched_contents}/3 stream contents extracted (+{pts})")

    # Final evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }