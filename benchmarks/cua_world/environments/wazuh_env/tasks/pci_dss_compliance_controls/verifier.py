#!/usr/bin/env python3
"""Verifier for pci_dss_compliance_controls task.

A GRC/Compliance Engineer must implement PCI DSS Requirement 10 controls in Wazuh:
custom SCA policy (>=5 checks), email alerting, detection rules, and compliance report.

Scoring (100 points total):
- Custom PCI DSS SCA policy with >=5 checks deployed: 25 pts
- Email alerting configured in ossec.conf (SMTP + to + from): 20 pts
- >=2 detection rules covering PCI DSS Req 10 violations (level >=10): 25 pts
- Compliance evidence report >=800 chars, created after task start: 20 pts
- ossec.conf meaningfully updated (email or new localfiles): 10 pts

Pass threshold: 65 points
Score cap: If report missing and score >= 65, cap at 64 (required deliverable)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65


def verify_pci_dss_compliance_controls(traj, env_info, task_info):
    """Verify PCI DSS compliance controls task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/pci_dss_compliance_controls_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: PCI DSS SCA policy with >=5 checks (25 pts)
        pci_policy = bool(result.get('pci_policy_found'))
        pci_checks = int(result.get('pci_check_count', 0))
        if pci_policy and pci_checks >= 5:
            score += 25
            subscores['sca_policy'] = True
            feedback_parts.append(f"PCI DSS SCA policy with {pci_checks} checks (25/25)")
        elif pci_policy and pci_checks >= 3:
            score += 15
            subscores['sca_policy'] = False
            feedback_parts.append(f"PCI DSS SCA policy found but only {pci_checks} checks (need >=5) (15/25)")
        elif pci_policy:
            score += 8
            subscores['sca_policy'] = False
            feedback_parts.append(f"PCI DSS SCA policy found but only {pci_checks} checks (8/25)")
        else:
            subscores['sca_policy'] = False
            feedback_parts.append("No PCI DSS SCA policy found in /var/ossec/etc/shared/ (0/25)")

        # Criterion 2: Email alerting configured (20 pts)
        email_conf = bool(result.get('email_configured'))
        email_to = bool(result.get('email_to_set'))
        email_smtp = bool(result.get('email_smtp_set'))
        email_from = bool(result.get('email_from_set'))

        email_fields = int(email_to) + int(email_smtp) + int(email_from)
        if email_conf and email_fields >= 3:
            score += 20
            subscores['email_alerting'] = True
            feedback_parts.append("Email alerting fully configured (smtp + from + to) (20/20)")
        elif email_conf and email_fields >= 2:
            score += 12
            subscores['email_alerting'] = False
            feedback_parts.append(f"Email partially configured ({email_fields}/3 fields set) (12/20)")
        elif email_conf:
            score += 6
            subscores['email_alerting'] = False
            feedback_parts.append("Email partially configured (1 field set) (6/20)")
        else:
            subscores['email_alerting'] = False
            feedback_parts.append("No email alerting configured in ossec.conf (0/20)")

        # Criterion 3: PCI DSS detection rules (25 pts)
        distinct_topics = int(result.get('distinct_pci_topics', 0))
        new_rules = int(result.get('new_rule_count', 0))
        high_level = bool(result.get('pci_rule_high_level'))

        if distinct_topics >= 2 and high_level:
            score += 25
            subscores['detection_rules'] = True
            feedback_parts.append(f"{distinct_topics} distinct PCI violation categories covered at level >=10 (25/25)")
        elif distinct_topics >= 2:
            score += 15
            subscores['detection_rules'] = False
            feedback_parts.append(f"{distinct_topics} categories covered but rules below level 10 (15/25)")
        elif distinct_topics >= 1 or new_rules >= 1:
            score += 8
            subscores['detection_rules'] = False
            feedback_parts.append(f"Only {distinct_topics} distinct PCI violation category covered (need >=2) (8/25)")
        else:
            subscores['detection_rules'] = False
            feedback_parts.append("No PCI DSS-relevant detection rules found (0/25)")

        # Criterion 4: Compliance evidence report (20 pts)
        report_exists = bool(result.get('report_exists'))
        report_size = int(result.get('report_size', 0))
        report_after = bool(result.get('report_after_start'))
        report_pci = bool(result.get('report_has_pci_content'))

        if report_exists and report_size >= 800 and report_after and report_pci:
            score += 20
            subscores['compliance_report'] = True
            feedback_parts.append(f"PCI compliance report: {report_size} chars with PCI DSS content (20/20)")
        elif report_exists and report_size >= 800 and report_after:
            score += 12
            subscores['compliance_report'] = False
            feedback_parts.append(f"Report ({report_size} chars) exists but lacks specific PCI DSS content (12/20)")
        elif report_exists and report_size >= 800:
            score += 8
            subscores['compliance_report'] = False
            feedback_parts.append(f"Report ({report_size} chars) may be pre-existing (not created after task start) (8/20)")
        elif report_exists:
            score += 3
            subscores['compliance_report'] = False
            feedback_parts.append(f"Report too short: {report_size} < 800 chars (3/20)")
        else:
            subscores['compliance_report'] = False
            feedback_parts.append("No report at /home/ga/Desktop/pci_compliance_report.txt (0/20)")

        # Criterion 5: ossec.conf meaningfully updated (10 pts)
        # Credit if email was configured (already counted) OR if new localfiles were added
        if subscores.get('email_alerting') or subscores.get('detection_rules'):
            score += 10
            subscores['ossec_updated'] = True
            feedback_parts.append("ossec.conf updated with alerting/monitoring configuration (10/10)")
        else:
            subscores['ossec_updated'] = False
            feedback_parts.append("ossec.conf not meaningfully updated (0/10)")

        # Score cap: report is a required deliverable
        if not subscores.get('compliance_report') and score >= PASS_THRESHOLD:
            score = PASS_THRESHOLD - 1
            feedback_parts.append(
                f"Score capped at {PASS_THRESHOLD - 1}: compliance report is a required deliverable"
            )

        passed = score >= PASS_THRESHOLD
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria met",
            "subscores": subscores
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run"
        }
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {e}"}
    except Exception as e:
        logger.exception("Verification error in pci_dss_compliance_controls")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
