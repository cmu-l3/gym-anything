#!/usr/bin/env python3
"""
Verifier for configure_hipaa_compliance_monitoring

Scoring (100 points total):
- HIPAA report file exported and modified after task start: 25 points
- Report contains HIPAA-specific vocabulary (from compliance section navigation): 20 points
- New alert profile created (PHI Unauthorized Access or similar): 30 points
- Log retention set to >= 2555 days: 25 points

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_configure_hipaa_compliance_monitoring(traj, env_info, task_info):
    """Verify HIPAA compliance monitoring configuration task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/configure_hipaa_compliance_result.json", tmp.name)
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

    # --- Criterion 1: HIPAA report file exported (25 pts) ---
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_size = result.get('report_size', 0)

    if report_exists and int(report_mtime) > int(task_start) and report_size > 100:
        score += 25
        subscores['report_exported'] = True
        feedback_parts.append(f"HIPAA compliance report exported ({report_size} bytes)")
    elif report_exists and report_size > 100:
        score += 10
        subscores['report_exported'] = False
        feedback_parts.append("Report file found but not created during this task session")
    else:
        subscores['report_exported'] = False
        feedback_parts.append("HIPAA compliance report not exported to ~/Desktop/hipaa_compliance_report.html")

    # --- Criterion 2: Report has HIPAA-specific vocabulary (20 pts) ---
    if result.get('has_hipaa_vocab', False):
        score += 20
        subscores['hipaa_content'] = True
        feedback_parts.append("Report contains HIPAA compliance section vocabulary")
    else:
        subscores['hipaa_content'] = False
        feedback_parts.append("Report missing HIPAA-specific content (may be a generic file, not from compliance section)")

    # --- Criterion 3: PHI alert profile created (30 pts) ---
    phi_alert_found = result.get('phi_alert_found', False)
    alert_created = result.get('alert_created', False)
    new_alert_count = result.get('new_alert_count', 0)

    if phi_alert_found:
        score += 30
        subscores['phi_alert'] = True
        feedback_parts.append("PHI/HIPAA alert profile created with appropriate name")
    elif alert_created and new_alert_count > 0:
        # New alert created but name doesn't match expected PHI keywords — partial credit
        score += 15
        subscores['phi_alert'] = False
        feedback_parts.append(f"New alert created ({new_alert_count} new) but not specifically named for PHI/HIPAA access")
    else:
        subscores['phi_alert'] = False
        feedback_parts.append("No new alert profile found (expected 'PHI Unauthorized Access' or similar)")

    # --- Criterion 4: Log retention set to >= 2555 days (25 pts) ---
    retention_set = result.get('retention_set', False)
    retention_days = result.get('log_retention_days', 0)

    if retention_set:
        score += 25
        subscores['retention_configured'] = True
        feedback_parts.append(f"Log retention configured to {retention_days} days (>= 2555 days required)")
    elif retention_days >= 365:
        # Set to some value but below HIPAA requirement — minimal credit
        score += 5
        subscores['retention_configured'] = False
        feedback_parts.append(f"Log retention set to {retention_days} days but HIPAA requires >= 2555 days (7 years)")
    else:
        subscores['retention_configured'] = False
        feedback_parts.append(f"Log retention not updated (current={retention_days} days, required=2555+ days)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
        "debug": {
            "report_mtime": report_mtime,
            "report_size": report_size,
            "task_start": task_start,
            "retention_days": retention_days,
            "new_alerts": new_alert_count,
        }
    }
