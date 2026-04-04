#!/usr/bin/env python3
"""
Verifier for Connect to Database task in DBeaver

Uses copy_from_env to read pre-exported verification data.
Requires:
1. Connection exists with exact name "Chinook"
2. Connection points to correct database path
3. Connection is SQLite type
4. Connection was created during this task (new connection)
5. Database is actually accessible
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_connect_to_database(traj, env_info, task_info):
    """
    Verify that a database connection was properly created.

    Criteria (stricter validation):
    1. Connection found in DBeaver config (REQUIRED)
    2. Connection name is exactly "Chinook" (REQUIRED - case-sensitive)
    3. Database path is correct (REQUIRED)
    4. Database type is SQLite (REQUIRED)
    5. New connection was added (connection count increased)
    6. Database is working/accessible
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_db_path = metadata.get('expected_db_path', '/home/ga/Documents/databases/chinook.db')
    expected_connection_name = metadata.get('expected_connection_name', 'Chinook')
    expected_db_type = metadata.get('expected_db_type', 'sqlite')
    require_exact_name = metadata.get('require_exact_name', True)

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/connect_result.json", temp_result.name)
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
        dbeaver_running = result.get('dbeaver_running', False)
        connection_found = result.get('connection_found', False)
        connection_name = result.get('connection_name', '')
        exact_name_match = result.get('exact_name_match', False)
        db_path = result.get('db_path', '')
        db_type = result.get('db_type', '')
        initial_count = result.get('initial_connection_count', 0)
        current_count = result.get('current_connection_count', 0)
        connection_working = result.get('connection_working', False)

        logger.info(f"Result: found={connection_found}, name={connection_name}, "
                   f"exact_match={exact_name_match}, path={db_path}")

        # CRITICAL CHECK 1: Connection must exist
        if not connection_found:
            critical_failures.append("No database connection found in DBeaver")
            return {
                "passed": False,
                "score": 0,
                "feedback": "FAILED: No database connection was created. " + " | ".join(critical_failures),
                "subscores": {
                    "connection_exists": False,
                    "exact_name": False,
                    "correct_path": False,
                    "correct_type": False,
                    "new_connection": False,
                    "connection_working": False
                }
            }

        # Criterion 1: Connection exists
        criteria_passed += 1
        feedback_parts.append("Connection exists in DBeaver")

        # CRITICAL CHECK 2: Exact name match required
        if require_exact_name:
            if exact_name_match:
                criteria_passed += 1
                feedback_parts.append(f"Connection name correct: '{connection_name}'")
            else:
                critical_failures.append(f"Connection name must be exactly 'Chinook', got '{connection_name}'")
                feedback_parts.append(f"WRONG NAME: '{connection_name}' (expected 'Chinook')")
        else:
            # Relaxed check - just needs to contain chinook
            if connection_name and expected_connection_name.lower() in connection_name.lower():
                criteria_passed += 1
                feedback_parts.append(f"Connection name contains 'Chinook': '{connection_name}'")
            else:
                feedback_parts.append(f"Name mismatch: '{connection_name}'")

        # Criterion 3: Database path must be correct
        if db_path == expected_db_path:
            criteria_passed += 1
            feedback_parts.append(f"Database path correct")
        else:
            critical_failures.append(f"Wrong database path: '{db_path}' (expected '{expected_db_path}')")
            feedback_parts.append(f"WRONG PATH: '{db_path}'")

        # Criterion 4: Database type must be SQLite
        if db_type.lower() == expected_db_type.lower():
            criteria_passed += 1
            feedback_parts.append(f"Database type correct: {db_type}")
        else:
            feedback_parts.append(f"Wrong type: '{db_type}' (expected '{expected_db_type}')")

        # Criterion 5: New connection was created (not pre-existing)
        if current_count > initial_count:
            criteria_passed += 1
            feedback_parts.append(f"New connection added (was {initial_count}, now {current_count})")
        elif current_count > 0:
            # Connection exists but may have been pre-existing - partial credit
            criteria_passed += 0.5
            feedback_parts.append(f"Connection exists but may be pre-existing")
        else:
            feedback_parts.append("No connections found")

        # Criterion 6: Database is working/accessible
        if connection_working:
            criteria_passed += 1
            feedback_parts.append("Database is accessible and working")
        else:
            feedback_parts.append("Could not verify database is accessible")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)

        # STRICT PASS REQUIREMENTS:
        # - Must have connection
        # - Must have exact name "Chinook" (if required)
        # - Must have correct path
        # - Must score at least 80%
        passed = (
            connection_found and
            (exact_name_match if require_exact_name else True) and
            db_path == expected_db_path and
            score >= 80
        )

        if critical_failures:
            feedback_parts.insert(0, "CRITICAL ISSUES: " + "; ".join(critical_failures))

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "connection_exists": connection_found,
                "exact_name": exact_name_match,
                "correct_path": db_path == expected_db_path,
                "correct_type": db_type.lower() == expected_db_type.lower(),
                "new_connection": current_count > initial_count,
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
