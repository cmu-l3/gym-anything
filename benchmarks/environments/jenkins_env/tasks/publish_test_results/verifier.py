#!/usr/bin/env python3
"""
Verifier for Publish Test Results task in Jenkins.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_publish_test_results(traj, env_info, task_info):
    """
    Verify that the test results pipeline was created and executed correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values
    metadata = task_info.get('metadata', {})
    expected_total = metadata.get('expected_total', 5)
    expected_fail = metadata.get('expected_fail', 1)
    expected_skip = metadata.get('expected_skip', 1)
    expected_pass = metadata.get('expected_pass', 3)
    expected_status = metadata.get('expected_status', 'UNSTABLE')

    try:
        # Load result JSON
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # 1. Job Existence (15 pts)
        if result.get('job_exists'):
            score += 15
            feedback_parts.append("Job created")
        else:
            feedback_parts.append("Job 'QA-Test-Suite' not found")
            return {"passed": False, "score": 0, "feedback": "Job not found"}

        # 2. Job Type (10 pts)
        job_class = result.get('job_class', '')
        if 'WorkflowJob' in job_class:
            score += 10
            feedback_parts.append("Job is Pipeline")
        else:
            feedback_parts.append(f"Job is not Pipeline (found {job_class})")

        # 3. Build Existence & Timing (15 pts)
        build_exists = result.get('build_exists')
        build_ts = result.get('build_timestamp', 0)
        task_start = result.get('task_start_time_ms', 0)
        
        if build_exists:
            # Check if build started after task start (anti-gaming)
            if build_ts > task_start:
                score += 15
                feedback_parts.append("Build executed")
            else:
                feedback_parts.append("Build timestamp predates task start")
        else:
            feedback_parts.append("No build executed")

        # 4. Build Result (10 pts)
        # We expect UNSTABLE because of the 1 failure
        build_result = result.get('build_result')
        if build_result == expected_status:
            score += 10
            feedback_parts.append(f"Build status correct ({expected_status})")
        else:
            feedback_parts.append(f"Build status incorrect: {build_result} (expected {expected_status})")

        # 5. Test Report Existence (15 pts)
        has_report = result.get('has_test_report')
        if has_report:
            score += 15
            feedback_parts.append("Test report found")
        else:
            feedback_parts.append("No test report published")

        # 6. Test Counts (35 pts total)
        counts = result.get('test_counts', {})
        total = counts.get('total', 0)
        fail = counts.get('fail', 0)
        skip = counts.get('skip', 0)
        passed = counts.get('pass', 0)

        if total == expected_total:
            score += 10
            feedback_parts.append(f"Total tests: {total}")
        else:
            feedback_parts.append(f"Wrong total tests: {total} (expected {expected_total})")

        if fail == expected_fail:
            score += 10
            feedback_parts.append(f"Failed tests: {fail}")
        else:
            feedback_parts.append(f"Wrong failed count: {fail} (expected {expected_fail})")

        if skip == expected_skip:
            score += 10
            feedback_parts.append(f"Skipped tests: {skip}")
        else:
            feedback_parts.append(f"Wrong skipped count: {skip} (expected {expected_skip})")

        if passed == expected_pass:
            score += 5
            feedback_parts.append(f"Passed tests: {passed}")
        else:
            feedback_parts.append(f"Wrong passed count: {passed} (expected {expected_pass})")

        # Final check
        # Must have at least created job and published report to pass
        passed = (score >= 60) and result.get('job_exists') and result.get('has_test_report')

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}