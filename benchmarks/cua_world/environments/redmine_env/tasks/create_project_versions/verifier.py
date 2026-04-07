#!/usr/bin/env python3
"""
Verifier for create_project_versions task.
checks:
1. Four specific versions created with correct names, dates, descriptions.
2. Two specific issues assigned to Phase 1.
3. VLM trajectory verification for UI interaction.
"""

import json
import os
import sys
import tempfile
import logging
from datetime import datetime

# Import VLM utils from framework
# Assuming gym_anything/vlm_utils.py pattern or similar available in environment
# If not available, we handle gracefully.

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_project_versions(traj, env_info, task_info):
    """
    Verifies that the agent created the 4 construction phases and assigned issues.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata (expected values)
    metadata = task_info.get('metadata', {})
    expected_versions = metadata.get('expected_versions', [])
    
    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Parse API data from result
    versions_data = result.get('final_versions_data', {}).get('versions', [])
    initial_count = int(result.get('initial_version_count', 0))
    
    # ---------------------------------------------------------
    # CRITERION 1: Anti-Gaming / Activity Check (10 pts)
    # ---------------------------------------------------------
    if len(versions_data) > initial_count:
        score += 10
        feedback.append("New versions detected.")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new versions created. Agent did nothing."
        }

    # ---------------------------------------------------------
    # CRITERION 2: Verify Versions (15 pts per version = 60 pts)
    # ---------------------------------------------------------
    # Each version: 5 pts name match, 5 pts date match, 5 pts description match
    
    # Helper to find a version matching a name fragment
    def find_version(fragment):
        for v in versions_data:
            if fragment.lower() in v.get('name', '').lower():
                return v
        return None

    phase1_id = None

    for exp in expected_versions:
        v = find_version(exp['name_fragment'])
        if v:
            # Name match
            score += 5
            
            # Date match
            if v.get('due_date') == exp['due_date']:
                score += 5
            else:
                feedback.append(f"Version '{exp['name_fragment']}' has wrong date: {v.get('due_date')} (expected {exp['due_date']})")
            
            # Description match
            desc = v.get('description', '')
            if exp['description_fragment'].lower() in desc.lower():
                score += 5
            else:
                feedback.append(f"Version '{exp['name_fragment']}' description mismatch.")
                
            # Capture Phase 1 ID for issue check
            if "phase 1" in exp['name_fragment'].lower():
                phase1_id = v.get('id')
        else:
            feedback.append(f"Version '{exp['name_fragment']}' not found.")

    # ---------------------------------------------------------
    # CRITERION 3: Verify Issue Assignments (15 pts per issue = 30 pts)
    # ---------------------------------------------------------
    issues_data = [result.get('issue1_data', {}).get('issue', {}), 
                   result.get('issue2_data', {}).get('issue', {})]
    
    for i, issue in enumerate(issues_data):
        issue_id = issue.get('id', 'unknown')
        fixed_version = issue.get('fixed_version', {})
        
        # Check if assigned to Phase 1
        # We check by ID if we found it, or by name as fallback
        assigned_correctly = False
        
        if phase1_id and fixed_version.get('id') == phase1_id:
            assigned_correctly = True
        elif "phase 1" in fixed_version.get('name', '').lower():
            assigned_correctly = True
            
        if assigned_correctly:
            score += 15
        else:
            feedback.append(f"Issue #{issue_id} not assigned to Phase 1 (current: {fixed_version.get('name', 'None')})")

    # ---------------------------------------------------------
    # OPTIONAL: VLM Trajectory Verification (Bonus / Confidence)
    # ---------------------------------------------------------
    # This task is heavily API verifiable, so VLM is supplementary.
    # We won't modify score based on VLM if API verification passes, 
    # but could use it to catch edge cases.
    
    passed = score >= 70  # Threshold: e.g., create versions correctly but miss assignment
    
    final_feedback = f"Score: {score}/100. " + " ".join(feedback)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }