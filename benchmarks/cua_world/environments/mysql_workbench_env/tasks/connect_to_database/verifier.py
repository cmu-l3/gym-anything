#!/usr/bin/env python3
"""
Verifier for Connect to Database task in MySQL Workbench

Verifies that a new database connection was created with correct parameters:
1. Connection exists in MySQL Workbench config
2. Connection name matches expected (SakilaDB)
3. Connection parameters are correct (localhost, 3306, ga)
4. Connection actually works
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_connect_to_database(traj, env_info, task_info):
    """
    Verify that a MySQL Workbench connection was created successfully.

    Criteria:
    1. Connection exists in config (REQUIRED)
    2. Connection name matches expected (SakilaDB)
    3. Correct host/port configuration
    4. Correct username
    5. New connection was added (not pre-existing)
    6. Connection is verified working
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get VLM function for visual verification
    query_vlm = env_info.get('query_vlm')

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_connection_name', 'SakilaDB')
    expected_host = metadata.get('expected_hostname', 'localhost')
    expected_port = metadata.get('expected_port', '3306')
    expected_user = metadata.get('expected_username', 'ga')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/connection_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        # Initialize scoring
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        critical_failures = []

        # Extract result data
        workbench_running = result.get('workbench_running', False)
        connection_found = result.get('connection_found', False)
        connection_name = result.get('connection_name', '')
        exact_name_match = result.get('exact_name_match', False)
        connection_host = result.get('connection_host', '')
        connection_port = result.get('connection_port', '')
        connection_user = result.get('connection_user', '')
        new_connection = result.get('new_connection', False)
        connection_working = result.get('connection_working', False)

        logger.info(f"Result: found={connection_found}, name={connection_name}, "
                   f"new={new_connection}, working={connection_working}")

        # CRITICAL CHECK 1: Connection must exist
        if not connection_found:
            critical_failures.append("No connection found in MySQL Workbench config")
            return {
                "passed": False,
                "score": 0,
                "feedback": "FAILED: No database connection created. Use MySQL Workbench to add a new connection.",
                "subscores": {
                    "connection_exists": False,
                    "exact_name": False,
                    "correct_host": False,
                    "correct_user": False,
                    "new_connection": False,
                    "connection_working": False
                }
            }

        # Criterion 1: Connection exists
        criteria_passed += 1
        feedback_parts.append("Connection created")

        # Criterion 2: Exact name match only (no partial matches allowed)
        if connection_name.lower() == expected_name.lower():
            criteria_passed += 1
            feedback_parts.append(f"Connection name correct: '{connection_name}'")
        elif connection_name:
            # Wrong name - no partial credit (task explicitly requires specific name)
            feedback_parts.append(f"WRONG NAME: Got '{connection_name}', expected '{expected_name}'")
        else:
            feedback_parts.append(f"MISSING NAME: Expected '{expected_name}'")

        # Criterion 3: Correct host (NO partial credit for wrong host)
        host_correct = False
        valid_hosts = [expected_host, '127.0.0.1', 'localhost']
        if connection_host and any(h in connection_host.lower() for h in valid_hosts):
            host_correct = True
            criteria_passed += 1
            feedback_parts.append(f"Host correct: {connection_host}")
        elif connection_host:
            feedback_parts.append(f"WRONG HOST: Got '{connection_host}'")
        else:
            feedback_parts.append("Host not configured")

        # Criterion 4: Correct username (NO partial credit for wrong user)
        if connection_user == expected_user:
            criteria_passed += 1
            feedback_parts.append(f"Username correct: {connection_user}")
        elif connection_user:
            feedback_parts.append(f"WRONG USER: Got '{connection_user}', expected '{expected_user}'")
        else:
            feedback_parts.append("Username not configured")

        # Criterion 5: New connection (not pre-existing)
        if new_connection:
            criteria_passed += 1
            feedback_parts.append("New connection added")
        else:
            # Still give partial credit if connection exists
            criteria_passed += 0.5
            feedback_parts.append("Connection may be pre-existing")

        # Criterion 6: Connection working
        if connection_working:
            criteria_passed += 1
            feedback_parts.append("Connection verified working")
        else:
            feedback_parts.append("Connection not verified working")

        # VLM visual verification if available
        vlm_verified = False
        if query_vlm:
            try:
                temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)

                    vlm_prompt = f"""Analyze this screenshot of MySQL Workbench.

                    Questions:
                    1. Is MySQL Workbench home screen visible?
                    2. Is there a connection tile/entry visible with the name '{expected_name}' or similar?
                    3. Does the connection appear to be configured (showing host/username)?

                    Respond with "VERIFIED" if you can see a database connection configured,
                    or "NOT VERIFIED" if no connection is visible.
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
                finally:
                    os.unlink(temp_screenshot.name)
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")

        if vlm_verified:
            feedback_parts.append("VLM: Connection visible")
        else:
            feedback_parts.append("VLM: Not verified")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)

        # PASS REQUIREMENTS:
        # - Connection must exist
        # - Name should match (or be close)
        # - Host should be correct
        # - Score >= 70%
        passed = (
            connection_found and
            (exact_name_match or expected_name.lower() in connection_name.lower()) and
            host_correct and
            score >= 70
        )

        if critical_failures:
            feedback_parts.insert(0, "CRITICAL: " + "; ".join(critical_failures))

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "connection_exists": connection_found,
                "exact_name": exact_name_match,
                "correct_host": host_correct,
                "correct_user": connection_user == expected_user,
                "new_connection": new_connection,
                "connection_working": connection_working
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
