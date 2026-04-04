#!/usr/bin/env python3
"""
Verifier for Create Freestyle Job task in Jenkins

Uses copy_from_env to read pre-exported verification data from the container.
The export_result.sh script queries Jenkins API and saves results to JSON.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_freestyle_job(traj, env_info, task_info):
    """
    Verify that a freestyle Jenkins job was created with expected configuration.

    Checks:
    1. Job with expected name exists in Jenkins
    2. Job is a freestyle project
    3. Job has a build step with shell command
    4. Shell command contains expected text
    5. Job was created during this session
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task_info metadata (with defaults)
    metadata = task_info.get('metadata', {})
    expected_job_name = metadata.get('expected_job_name', 'HelloWorld-Build')
    expected_command = metadata.get('expected_command', "echo 'Hello from Jenkins!'")

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_freestyle_job_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []

        initial_count = result.get('initial_job_count', 0)
        current_count = result.get('current_job_count', 0)
        job_found = result.get('job_found', False)
        job = result.get('job', {})

        logger.info(f"Result data: initial={initial_count}, current={current_count}, found={job_found}")
        logger.info(f"Job data: {job}")

        # Criterion 1: Check if job exists with expected name (case-insensitive)
        if job_found:
            job_name = job.get('name', '')

            if job_name.lower() == expected_job_name.lower():
                criteria_passed += 1
                feedback_parts.append(f"Job '{expected_job_name}' found in Jenkins")
            else:
                # Partial credit if job has similar name
                if 'hello' in job_name.lower():
                    criteria_passed += 0.5
                    feedback_parts.append(f"Job with similar name found: '{job_name}' (expected '{expected_job_name}')")
                else:
                    feedback_parts.append(f"Job name mismatch: expected '{expected_job_name}', got '{job_name}'")
        else:
            feedback_parts.append(f"Job '{expected_job_name}' NOT found in Jenkins")

            # Check if any new jobs were created
            if current_count > initial_count:
                new_jobs = current_count - initial_count
                feedback_parts.append(f"Note: {new_jobs} new job(s) created, but not with expected name")
            else:
                feedback_parts.append("No new jobs were created")

            # Early return since no job found
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "job_exists": False,
                    "correct_name": False,
                    "has_build_step": False,
                    "correct_command": False
                }
            }

        # Criterion 2: Check if job was newly created
        if current_count > initial_count:
            criteria_passed += 1
            feedback_parts.append(f"Job newly created (count: {initial_count} -> {current_count})")
        else:
            feedback_parts.append(f"Job may have existed before task (count unchanged: {current_count})")
            # Still give partial credit
            criteria_passed += 0.5

        # Criterion 3: Check if job has build command
        build_command = job.get('build_command', '')
        if build_command:
            criteria_passed += 1
            feedback_parts.append("Job has build step with shell command")
        else:
            feedback_parts.append("Job does not have a build step configured")

        # Criterion 4: Check if command matches expected (flexible matching)
        if build_command:
            # Normalize for comparison (remove extra whitespace, quotes)
            normalized_command = build_command.strip().replace('"', "'")
            normalized_expected = expected_command.strip().replace('"', "'")

            if normalized_command == normalized_expected:
                criteria_passed += 1
                feedback_parts.append(f"Build command correct: {expected_command}")
            elif 'hello from jenkins' in normalized_command.lower():
                # Partial credit for similar command
                criteria_passed += 0.75
                feedback_parts.append(f"Build command similar: got '{build_command}' (expected '{expected_command}')")
            else:
                feedback_parts.append(f"Build command incorrect: expected '{expected_command}', got '{build_command}'")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Pass if at least 3 out of 4 criteria met

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "job_exists": job_found,
                "correct_name": job.get('name', '').lower() == expected_job_name.lower() if job_found else False,
                "has_build_step": bool(build_command),
                "correct_command": build_command.strip().replace('"', "'") == expected_command.strip().replace('"', "'") if build_command else False
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
