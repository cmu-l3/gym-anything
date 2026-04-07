#!/usr/bin/env python3
"""
Verifier for schedule_weekly_lead_report task.
Evaluates the database state extracted during post_task hooks.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_weekly_lead_report(traj, env_info, task_info):
    """
    Verify that the Vtiger CRM report was created correctly with proper scheduling.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract task result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/schedule_report_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Anti-gaming check: Make sure a NEW report was created
    report_id = result.get("report_id", 0)
    initial_max_id = result.get("initial_max_id", 0)
    if report_id <= initial_max_id and result.get("report_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report found but existed prior to task start (Anti-gaming check failed)."
        }

    # 2. Basic report verification
    if not result.get("report_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report 'Weekly Lead Source Summary' was not found."
        }
    
    score += 20
    feedback_parts.append("Report created successfully")

    # 3. Check Module and Type
    module = str(result.get("primary_module", "")).lower()
    report_type = str(result.get("report_type", "")).lower()
    if module == "leads":
        score += 10
        feedback_parts.append("Primary module is Leads")
    else:
        feedback_parts.append(f"Wrong primary module: {module}")

    if report_type == "summary":
        score += 10
        feedback_parts.append("Report type is Summary")
    else:
        feedback_parts.append(f"Wrong report type: {report_type}")

    # 4. Check Grouping
    grouping_cols = str(result.get("grouping_cols", "")).lower()
    if "leadsource" in grouping_cols:
        score += 20
        feedback_parts.append("Grouping by Lead Source set")
    else:
        feedback_parts.append("Grouping by Lead Source missing")

    # 5. Check Schedule Settings
    sch_active = str(result.get("sch_active", "0")).lower()
    if sch_active in ["1", "true", "yes"]:
        score += 10
        feedback_parts.append("Scheduling is active")
    else:
        feedback_parts.append("Scheduling is NOT active")

    # Check Day (Friday is usually represented as '5' or part of a JSON array)
    sch_day = str(result.get("sch_day", ""))
    sch_type = str(result.get("sch_type", "")).lower()
    if "5" in sch_day or "friday" in sch_day.lower():
        score += 10
        feedback_parts.append("Scheduled day is Friday")
    else:
        feedback_parts.append(f"Scheduled day incorrect: {sch_day}")

    if "2" in sch_type or "week" in sch_type:
        score += 5
        feedback_parts.append("Schedule frequency is Weekly")

    # Check Time (17:00 / 5:00 PM)
    sch_time = str(result.get("sch_time", ""))
    if "17:00" in sch_time or "17:00:00" in sch_time:
        score += 10
        feedback_parts.append("Scheduled time is 17:00")
    else:
        feedback_parts.append(f"Scheduled time incorrect: {sch_time}")

    # Check Recipients
    sch_recipients = str(result.get("sch_recipients", ""))
    if sch_recipients.strip() != "" and len(sch_recipients) > 2:
        score += 5
        feedback_parts.append("Recipients configured")
    else:
        feedback_parts.append("Recipients missing")

    # Determine pass/fail
    # We require the report, module, type, grouping, and active schedule to be generally correct (>=80 pts)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }