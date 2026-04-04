#!/usr/bin/env python3
"""
Verifier for siem_hardening_and_user_audit

Scoring (100 points total):
- Hardening report file created after task start: 15 points
- contractor01 role downgraded from Admin to Operator: 30 points
- New user soc-analyst-02 created in ELA: 25 points
- Report correctly documents both contractor01 and soc-analyst-02: 30 points

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_siem_hardening_and_user_audit(traj, env_info, task_info):
    """Verify SIEM hardening and user audit task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/siem_hardening_result.json", tmp.name)
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

    # --- Criterion 1: Hardening report created after task start (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_size = result.get('report_size', 0)

    if report_exists and int(report_mtime) > int(task_start) and report_size > 50:
        score += 15
        subscores['report_created'] = True
        feedback_parts.append(f"Hardening report created ({report_size} bytes)")
    elif report_exists and report_size > 50:
        score += 5
        subscores['report_created'] = False
        feedback_parts.append("Report exists but not created during this task session")
    else:
        subscores['report_created'] = False
        feedback_parts.append("Hardening report not found at ~/Desktop/hardening_report.txt")

    # --- Criterion 2: contractor01 downgraded to Operator (30 pts) ---
    contractor01_downgraded = result.get('contractor01_downgraded', False)
    contractor01_role = result.get('contractor01_role', 'unknown')

    if contractor01_downgraded:
        score += 30
        subscores['contractor_downgraded'] = True
        feedback_parts.append(f"contractor01 successfully downgraded (role={contractor01_role})")
    elif contractor01_role not in ('unknown', ''):
        # Role was found but not changed to Operator
        subscores['contractor_downgraded'] = False
        feedback_parts.append(f"contractor01 role found ({contractor01_role}) but not downgraded to Operator")
    else:
        subscores['contractor_downgraded'] = False
        feedback_parts.append("contractor01 role not changed — still has excessive privileges")

    # --- Criterion 3: soc-analyst-02 created (25 pts) ---
    soc_created = result.get('soc_analyst_created', False)
    new_tech_count = result.get('new_tech_count', 0)

    if soc_created:
        score += 25
        subscores['new_analyst_created'] = True
        feedback_parts.append("New technician 'soc-analyst-02' created successfully")
    elif new_tech_count > 0:
        # New accounts were created but not soc-analyst-02 specifically
        score += 10
        subscores['new_analyst_created'] = False
        feedback_parts.append(f"New technician account(s) created ({new_tech_count}) but not 'soc-analyst-02'")
    else:
        subscores['new_analyst_created'] = False
        feedback_parts.append("New technician 'soc-analyst-02' not found in ELA")

    # --- Criterion 4: Report documents both accounts (30 pts) ---
    has_contractor = result.get('report_has_contractor', False)
    has_new_account = result.get('report_has_new_account', False)

    if has_contractor and has_new_account:
        score += 30
        subscores['report_complete'] = True
        feedback_parts.append("Report documents both contractor01 downgrade and soc-analyst-02 creation")
    elif has_contractor:
        score += 15
        subscores['report_complete'] = False
        feedback_parts.append("Report mentions contractor01 but not soc-analyst-02")
    elif has_new_account:
        score += 10
        subscores['report_complete'] = False
        feedback_parts.append("Report mentions soc-analyst-02 but not contractor01")
    else:
        subscores['report_complete'] = False
        feedback_parts.append("Report does not document the required account changes")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
        "debug": {
            "task_start": task_start,
            "report_mtime": report_mtime,
            "contractor01_role": contractor01_role,
            "new_tech_count": new_tech_count,
        }
    }
