#!/usr/bin/env python3
"""
Verifier for Configure Log Rotation task.
Verifies that 3 Jenkins jobs have specific BuildDiscarder policies applied.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_log_rotation(traj, env_info, task_info):
    """
    Verify log rotation settings for three jobs.
    
    Criteria:
    1. nightly-integration-tests: numToKeep=5, artifactNumToKeep=2
    2. feature-branch-builds: daysToKeep=7
    3. release-pipeline: numToKeep=10, artifactNumToKeep=5
    4. Configs must have changed (anti-gaming)
    5. Builds must not be manually deleted (count check)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Define expected values map
    # Values as strings to match XML extraction
    # -1 indicates "blank" or default
    requirements = {
        "nightly-integration-tests": {
            "numToKeep": "5", 
            "artifactNumToKeep": "2",
            "daysToKeep": "-1",
            "artifactDaysToKeep": "-1"
        },
        "feature-branch-builds": {
            "daysToKeep": "7",
            "numToKeep": "-1",
            "artifactNumToKeep": "-1",
            "artifactDaysToKeep": "-1"
        },
        "release-pipeline": {
            "numToKeep": "10",
            "artifactNumToKeep": "5",
            "daysToKeep": "-1",
            "artifactDaysToKeep": "-1"
        }
    }

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_log_rotation_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        jobs_data = result.get("jobs", [])
        if not jobs_data:
            return {"passed": False, "score": 0, "feedback": "No job data found in result"}
            
        score = 0
        max_score = 100
        feedback_parts = []
        
        # Track pass status per job
        jobs_passed = 0
        total_jobs = 3
        
        # Scoring Breakdown: 
        # 30 pts per job (10 for existence of rotator, 20 for correct values)
        # 10 pts for keeping build history integrity (not deleting builds)
        
        for job_req_name, reqs in requirements.items():
            # Find job data
            job_data = next((j for j in jobs_data if j["name"] == job_req_name), None)
            
            if not job_data:
                feedback_parts.append(f"Job {job_req_name} not found in analysis.")
                continue
                
            job_score = 0
            job_feedback = []
            
            # Check 1: Has LogRotator configured?
            if job_data.get("has_rotator") == "true" and job_data.get("config_changed") == "true":
                job_score += 10
            else:
                job_feedback.append("Log Rotation not enabled or config not saved")
            
            # Check 2: Values
            values_correct = True
            for field, expected_val in reqs.items():
                actual_val = job_data.get(field, "-1")
                # Handle blank/null as -1
                if actual_val in [None, ""]: actual_val = "-1"
                
                if actual_val != expected_val:
                    values_correct = False
                    job_feedback.append(f"{field}: expected {expected_val}, got {actual_val}")
            
            if values_correct:
                job_score += 20
            
            # Check 3: Build count (Anti-gaming: ensure manual delete wasn't used)
            # We created 12 builds. The policy doesn't run immediately unless explicitly triggered
            # or a new build runs. Simply configuring shouldn't delete builds immediately usually,
            # but even if it did, we expect SOME builds to remain based on policies.
            # Only fail if count is 0 or extremely low (indicating manual wipe).
            build_count = job_data.get("build_count", 0)
            if build_count < 2:
                job_feedback.append(f"Warning: Build count very low ({build_count}). Manual deletion suspected?")
                # Penalize slightly
                job_score = max(0, job_score - 5)
                
            score += job_score
            if job_score >= 25: # Mostly correct
                jobs_passed += 1
                
            if job_feedback:
                feedback_parts.append(f"{job_req_name}: " + ", ".join(job_feedback))
            else:
                feedback_parts.append(f"{job_req_name}: OK")

        # Global integrity bonus (10 pts) - if at least one job configured and no total wipe
        total_builds = sum(j.get("build_count", 0) for j in jobs_data)
        if total_builds > 5 and jobs_passed > 0:
            score += 10
        
        passed = (jobs_passed >= 3) and (score >= 90)
        
        return {
            "passed": passed,
            "score": min(100, score),
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}