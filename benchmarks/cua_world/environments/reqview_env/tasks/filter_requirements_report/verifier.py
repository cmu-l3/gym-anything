#!/usr/bin/env python3
"""
Verifier for filter_requirements_report task.

Strategy:
1. Ground Truth Calculation:
   - Load the actual SRS.json from the VM.
   - programmatic filter for "monitor" (case-insensitive) in text/heading.
   - Generate expected set of Requirement IDs.

2. Output Verification:
   - specific parsing of the agent's text report.
   - Compare reported count vs actual count.
   - Compare reported IDs vs expected IDs (Precision/Recall).

3. Visual Verification (VLM):
   - Check trajectory frames for the "Filter" bar presence or filtered view.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
PROJECT_BASE_DIR = "/home/ga/Documents/ReqView"
SRS_REL_PATH = "documents/SRS.json"
OUTPUT_REL_PATH = "/home/ga/Documents/ReqView/monitoring_report.txt"

def _strip_html(text):
    """Remove HTML tags from ReqView rich text fields."""
    if not text:
        return ""
    return re.sub(r'<[^>]+>', '', str(text)).strip()

def _get_ground_truth(srs_data, search_term):
    """
    Recursively find all requirements containing search_term.
    Returns a set of IDs.
    """
    matches = set()
    term = search_term.lower()

    def recursive_search(items):
        for item in items:
            # Check this item
            text = _strip_html(item.get('text', ''))
            heading = item.get('heading', '')
            
            # ReqView filter matches if term is in heading OR text
            if term in text.lower() or term in heading.lower():
                matches.add(item.get('id'))
            
            # Recurse into children
            if 'children' in item:
                recursive_search(item['children'])

    recursive_search(srs_data.get('data', []))
    return matches

def _parse_agent_report(report_content):
    """
    Parse the agent's text report.
    Expected format:
      Total Matches: N
      Matching Requirements:
      SRS-XX: ...
    """
    reported_count = 0
    reported_ids = set()
    
    lines = report_content.splitlines()
    for line in lines:
        line = line.strip()
        
        # Extract count
        if "Total Matches:" in line:
            try:
                parts = line.split(":")
                reported_count = int(parts[1].strip())
            except:
                pass
                
        # Extract IDs (look for patterns like "SRS-12:" or "SRS-123 ")
        # Regex looks for start of line ID pattern
        id_match = re.match(r'^(SRS-\d+)', line)
        if id_match:
            reported_ids.add(id_match.group(1)) # "SRS-123"
            
            # Also handle simple numbers if agent forgot prefix, though task says ID
            # But the ground truth IDs in JSON are usually just numbers "123"
            # We need to normalize. ReqView IDs in JSON are strings like "145".
            # The UI shows "SRS-145".
            
    # Normalize reported IDs to just the number part for comparison with JSON
    normalized_ids = set()
    for rid in reported_ids:
        # Strip non-digit characters to get the raw ID
        clean_id = re.sub(r'\D', '', rid)
        if clean_id:
            normalized_ids.add(clean_id)
            
    return reported_count, normalized_ids

def verify_filter_requirements_report(traj, env_info, task_info):
    """Verify the filtering and reporting task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    search_term = metadata.get('search_term', 'monitor')
    
    # 1. Load Task Result JSON (for timestamps/file existence)
    task_result = {}
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name) as f:
            task_result = json.load(f)
    except Exception:
        # If result file missing, task likely crashed or didn't run export
        pass
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    # 2. Check File Existence & Timestamp (Anti-gaming)
    if not task_result.get('output_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Report file not found at expected path."
        }
    
    if not task_result.get('file_created_during_task', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Report file exists but was not created/modified during this task session."
        }

    # 3. Load Ground Truth Data (SRS.json)
    # Construct path based on suffix from task_result or default
    project_dir = f"{PROJECT_BASE_DIR}/{task_result.get('project_path_suffix', 'filter_report_project')}"
    srs_path = f"{project_dir}/{SRS_REL_PATH}"
    
    srs_data = {}
    tmp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(srs_path, tmp_srs.name)
        with open(tmp_srs.name) as f:
            srs_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load SRS.json for verification: {e}"}
    finally:
        if os.path.exists(tmp_srs.name):
            os.unlink(tmp_srs.name)
            
    expected_ids = _get_ground_truth(srs_data, search_term)
    expected_count = len(expected_ids)
    
    # 4. Parse Agent Report
    report_content = ""
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(OUTPUT_REL_PATH, tmp_report.name)
        with open(tmp_report.name, 'r', errors='ignore') as f:
            report_content = f.read()
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)
            
    reported_count_val, reported_ids = _parse_agent_report(report_content)

    # 5. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion A: Report File Exists & Valid (already checked existence) -> 10 pts
    score += 10
    feedback_parts.append("Report file created.")

    # Criterion B: Format Check (Search Term & Total Matches headers) -> 10 pts
    if "Search Term:" in report_content and "Total Matches:" in report_content:
        score += 10
        feedback_parts.append("Report format valid.")
    else:
        feedback_parts.append("Report format invalid (missing headers).")

    # Criterion C: Accuracy of Total Count -> 20 pts
    if reported_count_val == expected_count:
        score += 20
        feedback_parts.append(f"Count correct ({expected_count}).")
    else:
        feedback_parts.append(f"Count mismatch (Reported: {reported_count_val}, Actual: {expected_count}).")

    # Criterion D: ID Recall (Found the right ones) -> 20 pts
    # We check intersection of IDs
    found_correct = reported_ids.intersection(expected_ids)
    recall = len(found_correct) / len(expected_ids) if expected_ids else 1.0
    recall_pts = int(20 * recall)
    score += recall_pts
    
    # Criterion E: ID Precision (Didn't hallucinate extras) -> 20 pts
    # Note: reported_ids might be empty if parsing failed
    if len(reported_ids) > 0:
        precision = len(found_correct) / len(reported_ids)
        precision_pts = int(20 * precision)
        score += precision_pts
    elif len(expected_ids) == 0:
        score += 20 # Correctly found nothing
    else:
        # Reported nothing, but expected something -> 0 precision pts
        pass
        
    feedback_parts.append(f"ID Recall: {len(found_correct)}/{len(expected_ids)}")

    # Criterion F: VLM Verification of UI Usage -> 20 pts
    # Use trajectory to see if filter bar was used
    frames = sample_trajectory_frames(traj, n=5)
    vlm_prompt = (
        "Does the interface show a requirements management tool with a search or filter bar active? "
        "Look for a search input field containing the text 'monitor' or a highlighted list of items."
        "Return JSON: {\"filter_visible\": boolean}"
    )
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res.get('parsed', {}).get('filter_visible', False):
            vlm_score = 20
            feedback_parts.append("VLM confirmed filter usage.")
        else:
            feedback_parts.append("VLM did not detect filter usage.")
    except Exception:
        feedback_parts.append("VLM verification failed.")
        
    score += vlm_score

    # Final Pass check
    # Need at least 60 points AND correct count
    passed = (score >= 60) and (reported_count_val == expected_count)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "expected_ids": list(expected_ids),
            "reported_ids": list(reported_ids),
            "vlm_score": vlm_score
        }
    }