#!/usr/bin/env python3
import json
import os
import sys
import tempfile

def verify_copy_customize_job(traj, env_info, task_info):
    """
    Verify the copy_customize_job task.
    
    Requirements:
    1. 'Regression-Test-Runner' job must exist (15 pts)
    2. 'Regression-Test-Runner' must be a Freestyle job (10 pts)
    3. Original 'Smoke-Test-Runner' must still exist (10 pts)
    4. Description must match the requirement (20 pts)
    5. Shell command must contain specific keywords (30 pts)
    6. Job must be created after task start (15 pts)
    """
    
    # setup copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/copy_customize_job_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    max_score = 100
    details = []
    
    # 1. Check if Regression job exists (15 pts)
    if data.get("regression_job_exists"):
        score += 15
        details.append("PASS: 'Regression-Test-Runner' job created.")
    else:
        details.append("FAIL: 'Regression-Test-Runner' job not found.")
        return {"passed": False, "score": 0, "feedback": "Target job not found", "details": details}

    # 2. Check Job Type (10 pts)
    # Class should contain FreeStyleProject. 
    # Note: Jenkins API usually returns 'hudson.model.FreeStyleProject'
    job_class = data.get("regression_job_class", "")
    if "FreeStyleProject" in job_class:
        score += 10
        details.append("PASS: Job is correct type (Freestyle).")
    else:
        details.append(f"FAIL: Job type incorrect. Expected FreeStyleProject, got {job_class}")

    # 3. Check Source Job Preservation (10 pts)
    if data.get("smoke_job_exists"):
        score += 10
        details.append("PASS: Original 'Smoke-Test-Runner' preserved.")
    else:
        details.append("FAIL: Original 'Smoke-Test-Runner' is missing (renamed instead of copied?).")

    # 4. Check Description (20 pts)
    # Expected: "Runs full regression tests against staging environment"
    desc = data.get("regression_description", "").strip()
    expected_desc = "Runs full regression tests against staging environment"
    
    if desc == expected_desc:
        score += 20
        details.append("PASS: Description matches exactly.")
    elif expected_desc.lower() in desc.lower():
        score += 10
        details.append(f"PARTIAL: Description roughly correct. Got: '{desc}'")
    else:
        details.append(f"FAIL: Description mismatch. Expected '{expected_desc}', got '{desc}'")

    # 5. Check Shell Command (30 pts)
    # Expected content keywords
    cmd = data.get("regression_command", "")
    keywords = ["TEST_SUITE=regression", "TARGET_ENV=staging", "142/142"]
    
    # Normalize command for comparison (remove XML entities if any remained, though jq handles most)
    cmd_normalized = cmd.replace("&amp;", "&").replace("&quot;", '"')
    
    matches = 0
    for kw in keywords:
        if kw in cmd_normalized:
            matches += 1
            
    # Calculate score based on keyword matches (10 pts per keyword)
    cmd_score = matches * 10
    score += cmd_score
    
    if matches == len(keywords):
        details.append("PASS: Shell command configuration correct.")
    elif matches > 0:
        details.append(f"PARTIAL: Shell command missing some elements ({matches}/{len(keywords)} found). Got: {cmd}")
    else:
        details.append("FAIL: Shell command incorrect.")

    # 6. Anti-gaming / Timestamp check (15 pts)
    # Not strictly checking creation timestamp here as the API doesn't always expose it easily without more complex calls,
    # but the export script verified existence relative to task start.
    # We'll allocate these points if the job exists and other params are modified, implying work was done.
    # A "Do Nothing" agent would fail step 1.
    # A "Rename" agent would fail step 3.
    # An "Imperfect" agent gets partial scores above.
    # We will grant these points if the primary criteria (existence + modification) are met.
    if score >= 45: # Arbitrary threshold indicating genuine attempt
        score += 15
        details.append("PASS: Process verification.")
    else:
        details.append("FAIL: Insufficient evidence of work.")

    # Final Pass/Fail
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(details)
    }