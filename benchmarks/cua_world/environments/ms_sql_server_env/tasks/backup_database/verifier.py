#!/usr/bin/env python3
"""
Verifier for Backup Database task in MS SQL Server environment.

Verifies that the agent:
1. Created a backup file at the expected location
2. The backup has a reasonable size
3. The backup is valid (RESTORE VERIFYONLY passed)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_backup_database(traj, env_info, task_info):
    """
    Verify that a database backup was created successfully.

    Criteria:
    1. Backup file exists (REQUIRED)
    2. Backup has reasonable size (REQUIRED)
    3. Backup is valid (REQUIRED)
    4. Backup was created recently
    5. SQL Server and Azure Data Studio running
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get VLM function for visual verification
    query_vlm = env_info.get('query_vlm')

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_backup_path = metadata.get('expected_backup_path', '/backup/AdventureWorks2022_backup.bak')
    min_backup_size_mb = metadata.get('min_backup_size_mb', 100)

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/backup_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        # Initialize scoring
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        critical_failures = []

        # Extract result data
        mssql_running = result.get('mssql_running', False)
        ads_running = result.get('ads_running', False)
        backup_exists = result.get('backup_exists', False)
        backup_size_mb = result.get('backup_size_mb', 0)
        backup_valid = result.get('backup_valid', False)
        backup_created_recently = result.get('backup_created_recently', False)
        reasonable_size = result.get('reasonable_size', False)

        logger.info(f"Result: backup_exists={backup_exists}, size={backup_size_mb}MB, "
                   f"valid={backup_valid}, recent={backup_created_recently}")

        # CRITICAL CHECK 1: Backup must exist
        if not backup_exists:
            critical_failures.append(f"Backup file not found at {expected_backup_path}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"FAILED: Backup file was not created at {expected_backup_path}",
                "subscores": {
                    "backup_exists": False,
                    "reasonable_size": False,
                    "backup_valid": False,
                    "created_recently": False,
                    "sql_server_running": mssql_running
                }
            }

        # Criterion 1: Backup exists (25 points)
        criteria_passed += 1
        feedback_parts.append(f"Backup file exists at {expected_backup_path}")

        # CRITICAL CHECK 2: Reasonable size
        if reasonable_size:
            criteria_passed += 1
            feedback_parts.append(f"Backup size: {backup_size_mb}MB (adequate for AdventureWorks)")
        elif backup_size_mb > 0:
            criteria_passed += 0.3
            feedback_parts.append(f"SMALL BACKUP: {backup_size_mb}MB (expected >= {min_backup_size_mb}MB)")
        else:
            critical_failures.append("Backup file is empty")
            feedback_parts.append("ERROR: Backup file has 0 bytes")

        # CRITICAL CHECK 3: Backup is valid
        if backup_valid:
            criteria_passed += 1
            feedback_parts.append("Backup verified successfully (RESTORE VERIFYONLY passed)")
        else:
            critical_failures.append("Backup verification failed")
            feedback_parts.append("WARNING: Backup may be corrupted or invalid")

        # Criterion 4: Backup created recently
        if backup_created_recently:
            criteria_passed += 1
            feedback_parts.append("Backup created during this task")
        else:
            criteria_passed += 0.5
            feedback_parts.append("Note: Backup may have been created earlier")

        # Criterion 5: SQL Server and ADS running
        if mssql_running:
            criteria_passed += 0.3
            feedback_parts.append("SQL Server running")
        if ads_running:
            criteria_passed += 0.2
            feedback_parts.append("Azure Data Studio running")

        # VLM verification if available
        vlm_verified = False
        if query_vlm:
            try:
                temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)

                    vlm_prompt = """Analyze this screenshot of Azure Data Studio or similar database tool.

                    Questions:
                    1. Is there a SQL Editor or query panel visible?
                    2. Is there a BACKUP DATABASE statement visible?
                    3. Are there success messages or completion indicators visible?

                    Respond with "VERIFIED" if you can see evidence of backup completion,
                    or "NOT VERIFIED" otherwise.
                    """

                    vlm_result = query_vlm(
                        image=temp_screenshot.name,
                        prompt=vlm_prompt
                    )

                    if vlm_result:
                        logger.info(f"VLM result: {vlm_result}")
                        vlm_text = str(vlm_result).upper()
                        if 'VERIFIED' in vlm_text and 'NOT VERIFIED' not in vlm_text:
                            vlm_verified = True
                            criteria_passed += 0.5
                            feedback_parts.append("VLM: Backup execution confirmed visually")
                finally:
                    os.unlink(temp_screenshot.name)
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                feedback_parts.append("VLM: Unavailable (verification skipped)")
        else:
            feedback_parts.append("VLM: Not configured (visual verification skipped)")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        score = min(score, 100)  # Cap at 100

        # STRICT PASS REQUIREMENTS:
        # - Backup must exist
        # - Must have reasonable size
        # - Must be valid
        # - Score >= 70%
        passed = (
            backup_exists and
            reasonable_size and
            backup_valid and
            score >= 70
        )

        if critical_failures:
            feedback_parts.insert(0, "CRITICAL: " + "; ".join(critical_failures))

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "backup_exists": backup_exists,
                "reasonable_size": reasonable_size,
                "backup_valid": backup_valid,
                "created_recently": backup_created_recently,
                "sql_server_running": mssql_running,
                "ads_running": ads_running,
                "vlm_verified": vlm_verified
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
