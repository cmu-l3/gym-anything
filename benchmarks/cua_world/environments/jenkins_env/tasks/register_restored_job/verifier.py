#!/usr/bin/env python3
"""
Verifier for Register Restored Job task.

Criteria:
1. Job "Legacy-Payroll" is visible in Jenkins API (40 pts)
   - Proves the config was loaded from disk.
2. Job has at least one build (30 pts)
   - Proves the agent interacted with the restored job.
3. Build result is SUCCESS (20 pts)
   - Proves the job configuration is valid and ran correctly.
4. NO system restart detected (10 pts)
   - Anti-gaming: Ensures 'Reload Configuration' was used, not a full restart.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_restored_job(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Retrieve result file
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/restored_job_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        # Extract metrics
        job_visible = result.get('job_visible', False)
        build_exists = result.get('build_exists', False)
        build_success = result.get('build_success', False)
        restart_detected = result.get('restart_detected', False)
        
        score = 0
        feedback_parts = []
        
        # Criterion 1: Job Registration (40 pts)
        if job_visible:
            score += 40
            feedback_parts.append("Job successfully registered and visible")
        else:
            feedback_parts.append("Job NOT visible in Jenkins")
            
        # Criterion 2: Build Execution (30 pts)
        if build_exists:
            score += 30
            feedback_parts.append("Build triggered successfully")
        else:
            feedback_parts.append("No build executed for the restored job")
            
        # Criterion 3: Build Success (20 pts)
        if build_success:
            score += 20
            feedback_parts.append("Build completed successfully")
        elif build_exists:
            feedback_parts.append("Build failed or unstable")
            
        # Criterion 4: Operational Safety / No Restart (10 pts)
        if not restart_detected:
            score += 10
            feedback_parts.append("Operational Safety: No system restart detected (Correct approach)")
        else:
            feedback_parts.append("PENALTY: System restart detected! Task required non-disruptive configuration reload.")
            # If restart was the ONLY way they got it to work, they fail the spirit of the task
            # We deduct the 10 points bonus, but arguably this is a partial failure.
            # However, scoring model says:
            # Job Visible (40) + Build (30) + Success (20) + No Restart (10) = 100
            # If they restart, max score is 90.
            
        passed = (score >= 70) and job_visible and build_exists

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed with error: {str(e)}"
        }