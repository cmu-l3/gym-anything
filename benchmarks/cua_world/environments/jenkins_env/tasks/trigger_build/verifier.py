#!/usr/bin/env python3
"""
Verifier for Trigger Build task in Jenkins

Checks if a build was triggered and completed successfully.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_trigger_build(traj, env_info, task_info):
    """
    Verify that a build was triggered and completed successfully.

    Checks:
    1. Test job exists in Jenkins
    2. A build was triggered (build count > 0)
    3. Build completed (not currently building)
    4. Build result is SUCCESS
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task_info metadata
    metadata = task_info.get('metadata', {})
    test_job_name = metadata.get('test_job_name', 'Test-Build-Job')
    expected_result = metadata.get('expected_result', 'SUCCESS')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/trigger_build_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []

        job_exists = result.get('job_exists', False)
        build_triggered = result.get('build_triggered', False)
        build_count = result.get('build_count', 0)
        last_build = result.get('last_build')

        logger.info(f"Result data: job_exists={job_exists}, build_triggered={build_triggered}, build_count={build_count}")
        logger.info(f"Last build: {last_build}")

        # Criterion 1: Check if test job exists
        if job_exists:
            criteria_passed += 1
            feedback_parts.append(f"Test job '{test_job_name}' exists in Jenkins")
        else:
            feedback_parts.append(f"Test job '{test_job_name}' NOT found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "job_exists": False,
                    "build_triggered": False,
                    "build_completed": False,
                    "build_successful": False
                }
            }

        # Criterion 2: Check if a build was triggered
        if build_triggered and build_count > 0:
            criteria_passed += 1
            feedback_parts.append(f"Build triggered successfully ({build_count} build(s))")
        else:
            feedback_parts.append(f"No build was triggered (build count: {build_count})")

        # Early return if no build
        if not last_build or last_build == "null":
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "job_exists": True,
                    "build_triggered": False,
                    "build_completed": False,
                    "build_successful": False
                }
            }

        # Criterion 3: Check if build completed (not still building)
        is_building = last_build.get('building', False)
        if not is_building:
            criteria_passed += 1
            feedback_parts.append("Build completed")
        else:
            feedback_parts.append("Build is still running (not completed)")

        # Criterion 4: Check if build was successful
        build_result = last_build.get('result', 'null')
        if build_result == expected_result:
            criteria_passed += 1
            feedback_parts.append(f"Build result: {build_result}")
        elif build_result == 'null' or build_result is None:
            feedback_parts.append("Build result not available (may still be running)")
        else:
            feedback_parts.append(f"Build failed: result is '{build_result}' (expected '{expected_result}')")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Pass if at least 3 out of 4 criteria met

        # Add build number to feedback if available
        build_number = last_build.get('number')
        if build_number:
            feedback_parts.append(f"Build #{build_number}")

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "job_exists": job_exists,
                "build_triggered": build_triggered and build_count > 0,
                "build_completed": not is_building,
                "build_successful": build_result == expected_result
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
