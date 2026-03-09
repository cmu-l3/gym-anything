#!/usr/bin/env python3
"""
Verifier for generate_system_report task.

Verifies:
1. Report file existence and freshness (Anti-gaming).
2. Report content accuracy against ground truth (Version, Repos, Storage).
3. VLM verification of admin panel navigation.
"""

import json
import os
import base64
import tempfile
import re
import logging
from typing import Dict, Any, List

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_system_report(traj, env_info, task_info):
    """
    Verify the system report task.
    
    Criteria:
    - File exists and was created during task (10 pts)
    - Correct Artifactory version (20 pts)
    - Correct Repository Count (15 pts)
    - All Repos listed (20 pts)
    - Repository types correct (15 pts)
    - Storage size mentioned (10 pts)
    - VLM: Evidence of Admin Panel navigation (10 pts)
    """
    
    # 1. Setup and data retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    # 2. Extract Ground Truth
    gt = result.get('ground_truth', {})
    gt_version = gt.get('version', {}).get('version', '').strip()
    gt_repos = gt.get('repos', [])
    
    # Ground truth derivations
    gt_repo_count = len(gt_repos)
    gt_repo_map = {r['key']: r.get('type', 'UNKNOWN').upper() for r in gt_repos}
    
    # 3. Extract User Report
    report_b64 = result.get('report_content_b64', '')
    report_text = ""
    if report_b64:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='replace')
        except:
            report_text = ""

    score = 0
    feedback_log = []

    # --- CRITERION 1: File Existence & Freshness (10 pts) ---
    if result.get('report_exists'):
        if result.get('file_created_during_task'):
            score += 10
            feedback_log.append("Report file created during task (10/10)")
        else:
            score += 5
            feedback_log.append("Report file exists but timestamp suggests pre-existence (5/10)")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file ~/system_report.txt not found."}

    # --- CRITERION 2: Version Check (20 pts) ---
    # Look for the exact version string in the text
    if gt_version and gt_version in report_text:
        score += 20
        feedback_log.append(f"Correct version '{gt_version}' found (20/20)")
    else:
        feedback_log.append(f"Version mismatch or missing. Expected '{gt_version}'")

    # --- CRITERION 3: Repository Count (15 pts) ---
    # Find numbers in lines containing 'count' or 'repositories'
    repo_count_match = re.search(r'(?:count|number|total).*?(\d+)', report_text, re.IGNORECASE)
    if repo_count_match:
        reported_count = int(repo_count_match.group(1))
        if reported_count == gt_repo_count:
            score += 15
            feedback_log.append(f"Correct repository count: {reported_count} (15/15)")
        else:
            feedback_log.append(f"Incorrect repository count. Found {reported_count}, expected {gt_repo_count}")
    else:
        # Fallback: Count lines that look like list items if no explicit count found
        # This is lenient but fair if the agent listed them but didn't write "Count: X"
        list_count = len(re.findall(r'^\s*[-*]\s+', report_text, re.MULTILINE))
        if list_count == gt_repo_count:
             score += 15
             feedback_log.append(f"Implicit repository count correct based on list items (15/15)")
        else:
             feedback_log.append("Could not verify repository count")

    # --- CRITERION 4: Repository Keys (20 pts) ---
    found_keys = 0
    for repo_key in gt_repo_map.keys():
        if repo_key in report_text:
            found_keys += 1
    
    if gt_repo_count > 0:
        key_score = int((found_keys / gt_repo_count) * 20)
        score += key_score
        feedback_log.append(f"Found {found_keys}/{gt_repo_count} repository keys ({key_score}/20)")
    else:
        score += 20 # Edge case: no repos to find
        feedback_log.append("No repositories to list (20/20)")

    # --- CRITERION 5: Repository Types (15 pts) ---
    # For every repo key found, check if its type (LOCAL, REMOTE, VIRTUAL) is nearby
    correct_types = 0
    checked_repos = 0
    
    for repo_key, repo_type in gt_repo_map.items():
        if repo_key in report_text:
            checked_repos += 1
            # Find the line containing the key
            for line in report_text.splitlines():
                if repo_key in line:
                    # Check if the correct type is in the same line (case insensitive)
                    if repo_type.upper() in line.upper():
                        correct_types += 1
                        break
                    # Handle common abbreviations or UI labels if strictly needed, 
                    # but Artifactory usually displays full type names.
    
    if checked_repos > 0:
        type_score = int((correct_types / checked_repos) * 15)
        score += type_score
        feedback_log.append(f"Correct types for {correct_types}/{checked_repos} listed repos ({type_score}/15)")
    else:
        if gt_repo_count == 0:
             score += 15
        else:
             feedback_log.append("No repository types verified (0/15)")

    # --- CRITERION 6: Storage Info (10 pts) ---
    # Look for a number followed by storage units
    if re.search(r'\d+(\.\d+)?\s*(B|KB|MB|GB|TB|bytes)', report_text, re.IGNORECASE):
        score += 10
        feedback_log.append("Storage information found (10/10)")
    else:
        feedback_log.append("No storage usage information found")

    # --- CRITERION 7: VLM Navigation Check (10 pts) ---
    # We use VLM to verify the agent actually visited the admin pages
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            Analyze these screenshots of a user interacting with JFrog Artifactory.
            I need to verify if the user navigated to the Administration section.
            
            Look for:
            1. The 'Administration' module selected (usually a gear icon or 'Administration' tab).
            2. Lists of repositories or System Info pages.
            3. "Storage" summary pages.
            
            Did the user visit the Admin/System/Repository configuration pages?
            Answer YES or NO, and explain briefly.
            """
            
            vlm_response = query_vlm(images=frames, prompt=prompt)
            
            if vlm_response and "YES" in vlm_response.get("result", "").upper():
                score += 10
                feedback_log.append("VLM: Admin navigation verified (10/10)")
            else:
                feedback_log.append("VLM: No clear evidence of Admin navigation (0/10)")
        else:
             feedback_log.append("VLM: No frames available for verification (0/10)")
             
    except ImportError:
        # Graceful fallback if library not available in test environment
        feedback_log.append("VLM: Library not available, skipping check (0/10)")

    # Final scoring logic
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }