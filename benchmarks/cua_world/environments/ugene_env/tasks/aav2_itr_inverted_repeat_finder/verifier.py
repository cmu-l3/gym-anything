#!/usr/bin/env python3
"""
Verifier for AAV2 ITR Inverted Repeat Finder task.
"""

import json
import os
import re
import tempfile
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_aav2_itr_inverted_repeat_finder(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    gb_exists = result.get('gb_exists', False)
    gb_valid = result.get('gb_valid', False)
    gb_created = result.get('gb_created_during_task', False)
    has_repeats = result.get('has_repeat_features', False)
    coords_str = result.get('repeat_coords', '')
    
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').lower()

    # 1. GenBank File Exists and Valid (15 pts)
    if gb_exists and gb_created and gb_valid:
        score += 15
        feedback_parts.append("Valid GenBank file created (+15)")
    elif gb_exists and gb_valid:
        score += 10
        feedback_parts.append("Valid GenBank file exists but may not have been created during task (+10)")
    else:
        feedback_parts.append("GenBank file missing or invalid (0)")

    # 2. Repeat Features Present (20 pts)
    if has_repeats:
        score += 20
        feedback_parts.append("Repeat features found in GenBank file (+20)")
    else:
        feedback_parts.append("No repeat features found in GenBank file (0)")

    # 3. Correct Repeat Coordinates (20 pts)
    found_5prime = False
    found_3prime = False
    if coords_str:
        pairs = re.findall(r'(\d+)\.\.(\d+)', coords_str)
        for start, end in pairs:
            s, e = int(start), int(end)
            if s <= 200 and e <= 200:
                found_5prime = True
            if s >= 4400 and e >= 4400:
                found_3prime = True
                
    if found_5prime and found_3prime:
        score += 20
        feedback_parts.append("Both 5' and 3' ITR coordinates found in annotations (+20)")
    elif found_5prime or found_3prime:
        score += 10
        feedback_parts.append("Only one ITR coordinate found in annotations (+10)")
    else:
        feedback_parts.append("Correct ITR coordinates not found in GenBank annotations (0)")

    # 4. Report exists (10 pts)
    if report_exists:
        score += 10
        feedback_parts.append("Report file exists (+10)")
        
        # 5. Correct genome length in report (15 pts)
        if '4679' in report_content:
            score += 15
            feedback_parts.append("Correct genome length found in report (+15)")
        else:
            feedback_parts.append("Correct genome length not found in report (0)")
            
        # 6. Correct ITR coordinates in report (10 pts)
        report_coords = re.findall(r'\d+', report_content)
        report_ints = [int(x) for x in report_coords]
        r_5prime = any(x <= 200 for x in report_ints) and any(x == 1 for x in report_ints)
        r_3prime = any(x >= 4500 for x in report_ints) and any(x >= 4600 for x in report_ints)
        
        if r_5prime and r_3prime:
            score += 10
            feedback_parts.append("Report contains accurate ITR coordinates (+10)")
        elif r_5prime or r_3prime:
            score += 5
            feedback_parts.append("Report contains partial ITR coordinates (+5)")
        else:
            feedback_parts.append("Report lacks correct ITR coordinates (0)")
    else:
        feedback_parts.append("Report file missing (0)")

    # 7. VLM verification of trajectory (10 pts)
    try:
        sys.path.insert(0, str(os.path.dirname(os.path.abspath(__file__))))
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = '''You are verifying a bioinformatics task in UGENE.
Task: Find inverted repeats in the AAV2 genome.
Check if the "Find repeats" dialog or Repeat Finder panel was opened at any point in these screenshots.
Return JSON:
{
    "find_repeats_used": true/false
}'''
        vlm_res = query_vlm(prompt=prompt, images=frames + [final])
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('find_repeats_used'):
            score += 10
            feedback_parts.append("VLM confirmed 'Find repeats' dialog was used (+10)")
        else:
            feedback_parts.append("VLM could not confirm 'Find repeats' usage")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # Give grace points if everything else is perfect
        if score == 90:
            score += 10
            feedback_parts.append("VLM check skipped, granting grace points (+10)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }