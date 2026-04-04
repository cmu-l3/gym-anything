#!/usr/bin/env python3
"""Verifier for sca_custom_policy_report task.

A compliance engineer must create a custom Wazuh SCA policy YAML file,
configure Wazuh to run it, and produce a compliance gap analysis report.

Scoring (100 points total):
- Custom SCA policy YAML file exists in Wazuh shared directory: 25 pts
- Policy has >= 3 custom security checks (valid structure): 20 pts
- ossec.conf references the custom policy (non-default policy in <sca> section): 20 pts
- Compliance report file exists at /home/ga/Desktop/compliance_report.txt: 20 pts
- Report is >= 500 characters (minimum analytical content): 15 pts

Pass threshold: 65 points

SCORE CAP: If the report is missing (report_exists=False) and score >= 65, cap at 64.
This prevents a scenario where all other criteria pass but the required report is absent.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65


def verify_sca_custom_policy_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/sca_custom_policy_report_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Custom SCA policy YAML file exists in Wazuh directory (25 pts)
        if result.get('custom_policy_exists'):
            score += 25
            subscores['policy_file'] = True
            policy_name = result.get('custom_policy_name', 'unknown')
            check_count = int(result.get('custom_policy_check_count', 0))
            feedback_parts.append(
                f"Custom SCA policy file found: '{policy_name}' "
                f"(detected ~{check_count} check entries)"
            )
        else:
            subscores['policy_file'] = False
            feedback_parts.append(
                "FAIL: No custom SCA policy YAML found in /var/ossec/etc/shared/ — "
                "create a YAML file following Wazuh SCA policy schema with policy: and checks: sections"
            )

        # Criterion 2: Policy has >= 3 checks (20 pts)
        check_count = int(result.get('custom_policy_check_count', 0))
        if result.get('custom_policy_exists') and check_count >= 3:
            score += 20
            subscores['check_coverage'] = True
            feedback_parts.append(
                f"Custom policy has {check_count} security checks (>= 3 required)"
            )
        elif result.get('custom_policy_exists') and check_count >= 1:
            score += 8
            subscores['check_coverage'] = False
            feedback_parts.append(
                f"Custom policy exists but only ~{check_count} check(s) detected (need >= 3)"
            )
        else:
            subscores['check_coverage'] = False
            if result.get('custom_policy_exists'):
                feedback_parts.append(
                    "Custom policy YAML found but no check entries detected — "
                    "verify YAML uses correct Wazuh SCA schema with 'checks:' section"
                )

        # Criterion 3: ossec.conf references the custom policy (20 pts)
        if result.get('ossec_has_custom_policy'):
            score += 20
            subscores['ossec_configured'] = True
            feedback_parts.append(
                "ossec.conf has custom (non-CIS-default) policy reference in <sca> section"
            )
        else:
            subscores['ossec_configured'] = False
            feedback_parts.append(
                "FAIL: ossec.conf does not reference a custom SCA policy — "
                "add <policy>etc/shared/your_policy.yml</policy> inside <sca> section of ossec.conf"
            )

        # Criterion 4: Compliance report exists (20 pts)
        if result.get('report_exists'):
            score += 20
            subscores['report_exists'] = True
            size = int(result.get('report_size_chars', 0))
            feedback_parts.append(
                f"Compliance gap analysis report created at /home/ga/Desktop/compliance_report.txt "
                f"({size} characters)"
            )
        else:
            subscores['report_exists'] = False
            feedback_parts.append(
                "FAIL: Compliance report not found at /home/ga/Desktop/compliance_report.txt"
            )

        # Criterion 5: Report has minimum content (15 pts)
        report_size = int(result.get('report_size_chars', 0))
        if result.get('report_exists') and report_size >= 500:
            score += 15
            subscores['report_content'] = True
            feedback_parts.append(f"Report has substantial content ({report_size} chars >= 500 required)")
        elif result.get('report_exists') and report_size >= 200:
            score += 7
            subscores['report_content'] = False
            feedback_parts.append(
                f"Report exists but is too short ({report_size} chars, need >= 500) — "
                f"include policy description, findings, and remediation steps"
            )
        else:
            subscores['report_content'] = False
            if result.get('report_exists'):
                feedback_parts.append(
                    f"Report file exists but contains only {report_size} chars — "
                    f"need >= 500 characters documenting SCA findings and custom policy"
                )

        # SCORE CAP: Report is required deliverable — cap score if missing
        if not result.get('report_exists') and score >= PASS_THRESHOLD:
            score = PASS_THRESHOLD - 1
            feedback_parts.append(
                f"Score capped at {PASS_THRESHOLD - 1}: "
                f"compliance report is a required deliverable that is missing"
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
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
