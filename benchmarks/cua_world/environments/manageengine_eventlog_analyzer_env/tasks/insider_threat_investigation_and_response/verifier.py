#!/usr/bin/env python3
"""
Verifier for insider_threat_investigation_and_response

Scoring (100 points total):
- Incident created with correct title/priority:           10 points
- Incident description contains attacker IP:                5 points
- Incident description contains secondary account:          5 points
- Incident count increased (anti-gaming):                   5 points
- Alert profile created:                                   10 points
- Alert has brute-force / service-account name:             5 points
- Alert count increased (anti-gaming):                      5 points
- Evidence PDF exists, created during task, valid:         15 points
- Report file exists, created during task:                  5 points
- Report contains attacker IP (10.55.3.88):                 8 points
- Report contains primary account (svc_dataops):            5 points
- Report contains secondary account (svc_reporting):        8 points
- Report mentions privilege escalation:                     7 points
- Report contains remediation recommendations:              7 points

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_insider_threat_investigation_and_response(traj, env_info, task_info):
    """Verify insider threat investigation and response task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/insider_threat_investigation_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export script may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    task_start = int(result.get('task_start', 0))

    # --- Criterion 1: Incident created (25 pts total) ---
    incident_found = result.get('incident_found', False)
    new_incident_count = result.get('new_incident_count', 0)

    if incident_found:
        score += 10
        subscores['incident_found'] = True
        feedback_parts.append("Security incident found in ELA")
    else:
        subscores['incident_found'] = False
        feedback_parts.append("No matching security incident found in ELA")

    if result.get('incident_has_ip', False):
        score += 5
        subscores['incident_has_ip'] = True
        feedback_parts.append("Incident contains attacker IP")
    else:
        subscores['incident_has_ip'] = False

    if result.get('incident_has_secondary', False):
        score += 5
        subscores['incident_has_secondary'] = True
        feedback_parts.append("Incident references secondary compromised account")
    else:
        subscores['incident_has_secondary'] = False

    if new_incident_count > 0:
        score += 5
        subscores['incident_count_increased'] = True
    else:
        subscores['incident_count_increased'] = False

    # --- Criterion 2: Alert profile created (20 pts total) ---
    alert_created = result.get('alert_created', False)
    brute_force_alert = result.get('brute_force_alert_found', False)

    if alert_created:
        score += 10
        subscores['alert_created'] = True
        feedback_parts.append("New alert profile created in ELA")
    else:
        subscores['alert_created'] = False
        feedback_parts.append("No new alert profile detected")

    if brute_force_alert:
        score += 5
        subscores['brute_force_alert_named'] = True
        feedback_parts.append("Alert profile has correct brute-force/service-account naming")
    else:
        subscores['brute_force_alert_named'] = False

    if result.get('new_alert_count', 0) > 0:
        score += 5
        subscores['alert_count_increased'] = True
    else:
        subscores['alert_count_increased'] = False

    # --- Criterion 3: Evidence PDF (15 pts) ---
    evidence_exists = result.get('evidence_exists', False)
    evidence_mtime = int(result.get('evidence_mtime', 0))
    evidence_size = int(result.get('evidence_size', 0))
    evidence_valid = result.get('evidence_valid_pdf', False)

    if evidence_exists and evidence_mtime > task_start and evidence_valid and evidence_size > 500:
        score += 15
        subscores['evidence_pdf'] = True
        feedback_parts.append(f"Evidence PDF exported ({evidence_size} bytes, valid PDF)")
    elif evidence_exists and evidence_size > 100:
        score += 5
        subscores['evidence_pdf'] = False
        feedback_parts.append("Evidence file exists but may be stale or invalid")
    else:
        subscores['evidence_pdf'] = False
        feedback_parts.append("Evidence PDF not found at ~/Desktop/insider_threat_evidence.pdf")

    # --- Criterion 4: Incident report file (40 pts total) ---
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    report_size = int(result.get('report_size', 0))

    if report_exists and report_mtime > task_start and report_size > 50:
        score += 5
        subscores['report_created'] = True
        feedback_parts.append(f"Incident report created ({report_size} bytes)")
    elif report_exists and report_size > 50:
        score += 2
        subscores['report_created'] = False
        feedback_parts.append("Report exists but not created during this task session")
    else:
        subscores['report_created'] = False
        feedback_parts.append("Incident report not found at ~/Desktop/insider_threat_report.txt")

    if result.get('has_attacker_ip', False):
        score += 8
        subscores['report_has_ip'] = True
        feedback_parts.append("Report contains attacker IP 10.55.3.88")
    else:
        subscores['report_has_ip'] = False
        feedback_parts.append("Report missing attacker IP")

    if result.get('has_primary_account', False):
        score += 5
        subscores['report_has_primary'] = True
        feedback_parts.append("Report contains primary account svc_dataops")
    else:
        subscores['report_has_primary'] = False

    if result.get('has_secondary_account', False):
        score += 8
        subscores['report_has_secondary'] = True
        feedback_parts.append("Report identifies secondary compromised account svc_reporting")
    else:
        subscores['report_has_secondary'] = False
        feedback_parts.append("Report does not identify secondary account svc_reporting")

    if result.get('has_escalation', False):
        score += 7
        subscores['report_has_escalation'] = True
        feedback_parts.append("Report documents privilege escalation")
    else:
        subscores['report_has_escalation'] = False

    if result.get('has_remediation', False):
        score += 7
        subscores['report_has_remediation'] = True
        feedback_parts.append("Report includes remediation recommendations")
    else:
        subscores['report_has_remediation'] = False

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
        "debug": {
            "task_start": task_start,
            "report_mtime": report_mtime,
            "report_size": report_size,
            "evidence_mtime": evidence_mtime,
            "evidence_size": evidence_size,
            "initial_alerts": result.get('initial_alert_count', 0),
            "current_alerts": result.get('current_alert_count', 0),
            "initial_incidents": result.get('initial_incident_count', 0),
            "current_incidents": result.get('current_incident_count', 0),
        }
    }
