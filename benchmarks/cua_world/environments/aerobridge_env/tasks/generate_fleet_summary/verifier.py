#!/usr/bin/env python3
"""
Verifier for generate_fleet_summary task.

Verifies:
1. File existence and creation time.
2. Presence of required sections.
3. Accuracy of extracted data against DB ground truth.
"""

import json
import base64
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fleet_summary(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    score = 0
    feedback_parts = []
    
    # 1. Check File Existence (10 pts)
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Report file /home/ga/Documents/fleet_summary.txt not found."}
    
    score += 10
    feedback_parts.append("File exists (+10)")

    # 2. Check Anti-Gaming (Created during task) (10 pts)
    if result.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task (+10)")
    else:
        feedback_parts.append("WARNING: File timestamp predates task start.")

    # Decode content
    try:
        content_b64 = result.get("output_content_b64", "")
        content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except Exception:
        content = ""

    if len(content.strip()) < 50:
        return {"passed": False, "score": score, "feedback": "File is empty or too short."}

    # 3. Check Sections (20 pts)
    required_sections = [
        "=== OPERATORS ===",
        "=== AIRCRAFT ===",
        "=== PERSONNEL ===",
        "=== SUMMARY ==="
    ]
    sections_found = 0
    for sec in required_sections:
        if sec in content:
            sections_found += 1
    
    section_score = int((sections_found / 4) * 20)
    score += section_score
    feedback_parts.append(f"Sections found: {sections_found}/4 (+{section_score})")

    # 4. Content Verification vs Ground Truth
    gt = result.get("ground_truth", {})
    gt_counts = gt.get("counts", {})
    gt_ops = gt.get("operators", [])
    gt_ac = gt.get("aircraft", [])
    gt_ppl = gt.get("persons", [])

    content_lower = content.lower()

    # Check Summary Counts (20 pts)
    # We look for the numbers in the SUMMARY section (simple heuristic)
    summary_score = 0
    try:
        summary_section = content.split("=== SUMMARY ===")[1]
        
        if str(gt_counts['operators']) in summary_section: summary_score += 5
        if str(gt_counts['aircraft']) in summary_section: summary_score += 5
        if str(gt_counts['persons']) in summary_section: summary_score += 5
        if str(gt_counts['flight_plans']) in summary_section: summary_score += 5
    except IndexError:
        pass # Summary section missing/empty
    
    score += summary_score
    feedback_parts.append(f"Summary counts match (+{summary_score}/20)")

    # Check Operators Data (20 pts)
    # Check if operator names are present
    ops_found = 0
    for op in gt_ops:
        if op['name'].lower() in content_lower:
            ops_found += 1
    
    if len(gt_ops) > 0:
        op_score = int((ops_found / len(gt_ops)) * 20)
    else:
        op_score = 20 # No operators to find
    
    score += op_score
    feedback_parts.append(f"Operators found: {ops_found}/{len(gt_ops)} (+{op_score})")

    # Check Aircraft Data (20 pts)
    # Check if random sample of aircraft names are present
    ac_found = 0
    # check max 5 aircraft to avoid huge processing if list is long
    check_list = gt_ac[:10] 
    for ac in check_list:
        if ac['name'].lower() in content_lower:
            ac_found += 1
            
    if len(check_list) > 0:
        ac_score = int((ac_found / len(check_list)) * 20)
    else:
        ac_score = 20
        
    score += ac_score
    feedback_parts.append(f"Aircraft sample found: {ac_found}/{len(check_list)} (+{ac_score})")

    # Final Result
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }