#!/usr/bin/env python3
"""
Verifier for extend_aircraft_model task.

Scores the agent on:
1. Creating a valid Django migration (15 pts)
2. Updating the database schema correctly (20 pts)
3. Correct column configuration (nullable integer) (10 pts)
4. Backfilling data for existing records (25 pts)
5. Updating the admin panel configuration (15 pts)
6. Keeping the server running (10 pts)
7. Anti-gaming (migration creation time) (5 pts)

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extend_aircraft_model(traj, env_info, task_info):
    """
    Verify the extend_aircraft_model task via exported JSON.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Unpack verification data
    migration_exists = result.get('migration_file_exists', False)
    migration_fresh = result.get('migration_created_during_task', False)
    admin_updated = result.get('admin_updated', False)
    server_code = result.get('server_status_code', '000')
    
    db_check = result.get('db_check', {})
    column_exists = db_check.get('column_exists', False)
    is_integer = db_check.get('is_integer', False)
    allows_null = db_check.get('allows_null', False)
    
    total_aircraft = db_check.get('total_aircraft', 0)
    count_120 = db_check.get('count_with_120', 0)
    count_null = db_check.get('count_null', 0)

    # Criterion 1: Migration file (15 pts)
    if migration_exists:
        score += 15
        feedback_parts.append("Migration file found (+15)")
    else:
        feedback_parts.append("No migration file found containing 'max_altitude_m'")

    # Criterion 2: Database column exists (20 pts)
    if column_exists:
        score += 20
        feedback_parts.append("Database column created (+20)")
    else:
        feedback_parts.append("Database column 'max_altitude_m' does not exist")

    # Criterion 3: Column configuration (10 pts)
    if column_exists:
        if is_integer and allows_null:
            score += 10
            feedback_parts.append("Column type is Integer/Nullable (+10)")
        elif is_integer:
            score += 5
            feedback_parts.append("Column is Integer but NOT nullable (+5)")
        else:
            feedback_parts.append("Column type incorrect (not Integer)")

    # Criterion 4: Data population (25 pts)
    # Require strict adherence: all records must be 120.
    if total_aircraft > 0:
        if count_120 == total_aircraft:
            score += 25
            feedback_parts.append(f"All {total_aircraft} aircraft records updated to 120m (+25)")
        elif count_120 > 0:
            # Partial credit
            pct = count_120 / total_aircraft
            partial = int(25 * pct)
            score += partial
            feedback_parts.append(f"Partially updated data ({count_120}/{total_aircraft}) (+{partial})")
        else:
            feedback_parts.append("No aircraft records were updated to 120m")
    else:
        # Edge case: no aircraft in DB? (Shouldn't happen with fixture data)
        feedback_parts.append("No aircraft found in database to verify")

    # Criterion 5: Admin updated (15 pts)
    if admin_updated:
        score += 15
        feedback_parts.append("Admin configuration updated (+15)")
    else:
        feedback_parts.append("Admin file not updated with new field")

    # Criterion 6: Server health (10 pts)
    if str(server_code) in ['200', '302']:
        score += 10
        feedback_parts.append("Server is running and accessible (+10)")
    else:
        feedback_parts.append(f"Server is down or returning error (HTTP {server_code})")

    # Criterion 7: Anti-gaming (5 pts)
    if migration_fresh:
        score += 5
        feedback_parts.append("Migration created during task (+5)")
    elif migration_exists:
        feedback_parts.append("Migration file timestamp predates task start (suspicious)")

    # Final verdict
    passed = score >= 70
    
    # Additional requirement: Must have at least created the column and updated data
    # (Prevents passing on auxiliary points alone)
    critical_criteria = column_exists and (count_120 > 0)
    if not critical_criteria:
        passed = False
        feedback_parts.append("CRITICAL FAIL: Column must exist and data must be updated to pass.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }