#!/usr/bin/env python3
"""
Verifier for forensic_export_and_scheduled_reporting

Scoring (100 points total):
- CSV export file created after task start and non-empty: 25 points
- Scheduled report created (with daily frequency or SOC/security name): 25 points
- Log archival policy with >= 730 day retention found: 25 points
- Root access alert profile created: 25 points

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_forensic_export_and_scheduled_reporting(traj, env_info, task_info):
    """Verify forensic export and scheduled reporting task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/forensic_export_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    task_start = result.get('task_start', 0)

    # --- Criterion 1: CSV export file created after task start (25 pts) ---
    csv_exists = result.get('csv_exists', False)
    csv_mtime = result.get('csv_mtime', 0)
    csv_size = result.get('csv_size', 0)

    if csv_exists and int(csv_mtime) > int(task_start) and csv_size > 100:
        score += 25
        subscores['csv_exported'] = True
        feedback_parts.append(f"CSV export created ({csv_size} bytes)")
    elif csv_exists and csv_size > 100:
        score += 10
        subscores['csv_exported'] = False
        feedback_parts.append("CSV file found but appears to be from a prior session")
    elif csv_exists:
        score += 5
        subscores['csv_exported'] = False
        feedback_parts.append(f"CSV file created but nearly empty ({csv_size} bytes)")
    else:
        subscores['csv_exported'] = False
        feedback_parts.append("CSV export not found at ~/Desktop/root_activity_export.csv")

    # --- Criterion 2: Scheduled report created (25 pts) ---
    report_created = result.get('report_created', False)
    daily_report = result.get('daily_report_found', False)
    soc_report = result.get('soc_report_found', False)
    new_report_count = result.get('new_report_count', 0)

    if (daily_report or soc_report) and report_created:
        score += 25
        subscores['scheduled_report'] = True
        feedback_parts.append("Daily SOC/security scheduled report created")
    elif report_created and new_report_count > 0:
        score += 15
        subscores['scheduled_report'] = False
        feedback_parts.append(f"Scheduled report created ({new_report_count} new) but not set as daily or named for SOC")
    else:
        subscores['scheduled_report'] = False
        feedback_parts.append("No scheduled report created (navigate to Reports section)")

    # --- Criterion 3: Log archival >= 730 days (25 pts) ---
    archive_found = result.get('archive_found', False)
    archive_days = result.get('archive_days', 0)

    if archive_found:
        score += 25
        subscores['archival_configured'] = True
        feedback_parts.append(f"Legal evidence hold archival configured ({archive_days} days retention)")
    elif archive_days > 0:
        score += 5
        subscores['archival_configured'] = False
        feedback_parts.append(f"Archive policy found but only {archive_days} days (need >= 730 days)")
    else:
        subscores['archival_configured'] = False
        feedback_parts.append("No log archival policy with 730+ day retention found")

    # --- Criterion 4: Root access alert created (25 pts) ---
    root_alert = result.get('root_alert_found', False)
    alert_created = result.get('alert_created', False)
    new_alert_count = result.get('new_alert_count', 0)

    if root_alert:
        score += 25
        subscores['root_alert'] = True
        feedback_parts.append("Root Access Monitor alert profile created")
    elif alert_created and new_alert_count > 0:
        score += 12
        subscores['root_alert'] = False
        feedback_parts.append(f"New alert created ({new_alert_count}) but not named for root access monitoring")
    else:
        subscores['root_alert'] = False
        feedback_parts.append("No Root Access Monitor alert profile found")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
        "debug": {
            "task_start": task_start,
            "csv_mtime": csv_mtime,
            "csv_size": csv_size,
            "archive_days": archive_days,
            "new_reports": new_report_count,
            "new_alerts": new_alert_count,
        }
    }
