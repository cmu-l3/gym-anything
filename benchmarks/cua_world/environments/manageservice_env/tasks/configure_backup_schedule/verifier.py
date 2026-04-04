#!/usr/bin/env python3
"""
Verifier for configure_backup_schedule task.
Checks ServiceDesk Plus database configuration for backup settings.
"""

import sys
import os
import json
import logging
import csv
import io
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_csv_data(csv_content):
    """Parse pipe-separated CSV content with headers."""
    if not csv_content or not csv_content.strip():
        return []
    try:
        reader = csv.DictReader(io.StringIO(csv_content), delimiter='|')
        return list(reader)
    except Exception as e:
        logger.warning(f"Failed to parse CSV: {e}")
        return []

def verify_backup_schedule(traj, env_info, task_info):
    """
    Verify backup schedule configuration.
    
    Criteria:
    1. Schedule enabled
    2. Time set to 02:00
    3. Retention set to 7 days
    4. Email set to admin@example.com
    5. Notification enabled
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_email = metadata.get("expected_email", "admin@example.com")
    expected_retention = str(metadata.get("expected_retention_days", 7))
    
    # Load main result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Load table CSVs
    tables_data = {}
    for table_name, info in result.get("tables", {}).items():
        if info.get("found"):
            path = info.get("path")
            if path:
                temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
                try:
                    copy_from_env(path, temp_csv.name)
                    with open(temp_csv.name, 'r') as f:
                        tables_data[table_name] = parse_csv_data(f.read())
                except Exception as e:
                    logger.warning(f"Failed to load table {table_name}: {e}")
                finally:
                    if os.path.exists(temp_csv.name):
                        os.unlink(temp_csv.name)
    
    score = 0
    feedback = []
    
    # FIND THE CONFIGURATION
    # We look through loaded tables for the relevant row
    backup_config = {}
    
    # Strategy 1: periodic_backup_schedule (common in recent versions)
    # Columns often: SCHEDULE_ID, START_TIME, PERIOD_TYPE, BACKUP_TYPE, NO_OF_DAYS, EMAIL_ID, SEND_MAIL, ENABLED
    if "periodic_backup_schedule" in tables_data and tables_data["periodic_backup_schedule"]:
        # Usually there is only one row, or one active row
        rows = tables_data["periodic_backup_schedule"]
        # Find the most recently updated or the enabled one
        for row in rows:
            # Normalize keys to lowercase
            r = {k.lower(): v for k, v in row.items()}
            backup_config = r
            break # Assume first row is the config
            
    # Strategy 2: backupschedule (older versions)
    elif "backupschedule" in tables_data and tables_data["backupschedule"]:
        rows = tables_data["backupschedule"]
        for row in rows:
            r = {k.lower(): v for k, v in row.items()}
            backup_config = r
            break

    if not backup_config:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Could not find backup configuration in database tables."
        }

    logger.info(f"Found config: {backup_config}")

    # VERIFY ENABLED (30 pts)
    # Field names vary: 'enabled', 'status', 'schedulestatus'
    is_enabled = False
    status_val = str(backup_config.get('enabled', backup_config.get('status', 'false'))).lower()
    if status_val in ['true', '1', 'enabled', 'active']:
        is_enabled = True
        score += 30
        feedback.append("Backup schedule is enabled")
    else:
        feedback.append("Backup schedule is NOT enabled")

    # VERIFY TIME (20 pts)
    # Field often 'start_time' or 'schedule_time'. 
    # Format might be milliseconds, HH:MM, or timestamp
    time_val = str(backup_config.get('start_time', backup_config.get('schedule_time', '0')))
    
    # Check for 02:00 or 14:00 or millisecond equivalent
    # 2:00 AM in millis from start of day = 2 * 3600 * 1000 = 7200000
    # Or just "02:00" string
    time_correct = False
    if '02:00' in time_val or '2:00' in time_val or time_val == '7200000':
        time_correct = True
        score += 20
        feedback.append("Time is set to 02:00")
    else:
        feedback.append(f"Time incorrect (found {time_val}, expected 02:00)")

    # VERIFY RETENTION (20 pts)
    # Field often 'no_of_days' or 'retention_count'
    retention_val = str(backup_config.get('no_of_days', backup_config.get('backup_retention_count', '0')))
    if retention_val == expected_retention:
        score += 20
        feedback.append(f"Retention set to {expected_retention} days")
    else:
        feedback.append(f"Retention incorrect (found {retention_val}, expected {expected_retention})")

    # VERIFY EMAIL (15 pts)
    # Field often 'email_id' or 'email_ids'
    email_val = str(backup_config.get('email_id', backup_config.get('email_ids', ''))).lower()
    if expected_email in email_val:
        score += 15
        feedback.append(f"Notification email set to {expected_email}")
    else:
        feedback.append(f"Email incorrect (found {email_val})")

    # VERIFY NOTIFICATION ENABLED (15 pts)
    # Field often 'send_mail'
    notify_val = str(backup_config.get('send_mail', 'false')).lower()
    if notify_val in ['true', '1', 'y', 'yes']:
        score += 15
        feedback.append("Failure notification enabled")
    else:
        # If email is set but flag is missing/false, strict check fails
        feedback.append("Failure notification flag not enabled")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }