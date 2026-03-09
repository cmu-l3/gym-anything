#!/usr/bin/env python3
"""Verifier for incident_correlation_response task.

A detection engineer must investigate real Wazuh alerts, create a correlation rule
with frequency/timeframe-based detection, configure active response, and write
an incident investigation report.

Scoring (100 points total):
- Correlation rule with frequency + timeframe attributes exists: 30 pts
  (bonus +10 if rule has level >= 13)
- Active response configured in ossec.conf: 25 pts
- Incident report exists at /home/ga/Desktop/incident_report.txt: 20 pts
- Report was created after task start (not pre-existing): 15 pts
- Report has >= 300 characters: 10 pts

Note: The +10 bonus for level >= 13 means max possible score is 110 (capped at 100).
Pass threshold: 65 points

SCORE CAP: If the report is missing, cap score to prevent passing on config alone.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65


def verify_incident_correlation_response(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/incident_correlation_response_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Correlation rule with frequency + timeframe attributes (30 pts, +10 bonus if level >= 13)
        if result.get('correlation_rule_exists'):
            score += 30
            subscores['correlation_rule'] = True
            level = int(result.get('correlation_rule_level', 0))
            freq = int(result.get('correlation_rule_frequency', 0))
            timeframe = int(result.get('correlation_rule_timeframe', 0))
            feedback_parts.append(
                f"Correlation rule created with frequency={freq} occurrences "
                f"within timeframe={timeframe}s (level {level})"
            )
            if level >= 13:
                score = min(score + 10, 100)  # Bonus, capped at 100 total
                subscores['level_requirement'] = True
                feedback_parts.append(f"Rule meets level >= 13 requirement (level {level})")
            elif level >= 10:
                subscores['level_requirement'] = False
                feedback_parts.append(
                    f"Rule level {level} is below recommended level 13 "
                    f"(correlation should escalate to high severity)"
                )
            else:
                subscores['level_requirement'] = False
                feedback_parts.append(
                    f"Rule level {level} is too low — correlation rules should be level 13+ "
                    f"to represent escalated threat severity"
                )
        else:
            subscores['correlation_rule'] = False
            subscores['level_requirement'] = False
            feedback_parts.append(
                "FAIL: No correlation rule found with both 'frequency' and 'timeframe' attributes "
                "in local_rules.xml — these are required for Wazuh composite/frequency-based rules"
            )

        # Criterion 2: Active response configured (25 pts)
        if result.get('active_response_configured'):
            score += 25
            subscores['active_response'] = True
            feedback_parts.append("Active response configured in Wazuh ossec.conf")
        else:
            subscores['active_response'] = False
            feedback_parts.append(
                "FAIL: No active response configuration found or updated in ossec.conf — "
                "add an <active-response> block referencing your correlation rule"
            )

        # Criterion 3: Incident report exists (20 pts)
        if result.get('report_exists'):
            score += 20
            subscores['report_exists'] = True
            feedback_parts.append(
                "Incident investigation report created at /home/ga/Desktop/incident_report.txt"
            )
        else:
            subscores['report_exists'] = False
            feedback_parts.append(
                "FAIL: Incident report not found at /home/ga/Desktop/incident_report.txt"
            )

        # Criterion 4: Report created after task start (15 pts)
        if result.get('report_exists') and result.get('report_created_after_start'):
            score += 15
            subscores['report_timestamp'] = True
            feedback_parts.append("Report was created after task start (not pre-existing)")
        elif result.get('report_exists'):
            subscores['report_timestamp'] = False
            feedback_parts.append(
                "FAIL: Report file exists but was not created during this task "
                "(timestamp predates task start)"
            )
        else:
            subscores['report_timestamp'] = False

        # Criterion 5: Report has minimum content (10 pts)
        report_size = int(result.get('report_size_chars', 0))
        if result.get('report_exists') and report_size >= 300:
            score += 10
            subscores['report_content'] = True
            feedback_parts.append(f"Report has adequate content ({report_size} chars >= 300 required)")
        elif result.get('report_exists'):
            subscores['report_content'] = False
            feedback_parts.append(
                f"Report too short ({report_size} chars) — need >= 300 chars documenting "
                f"the investigated events, correlation pattern, and response actions"
            )
        else:
            subscores['report_content'] = False

        # SCORE CAP: Report is a required deliverable — cap score if missing
        if not result.get('report_exists') and score >= PASS_THRESHOLD:
            score = PASS_THRESHOLD - 1
            feedback_parts.append(
                f"Score capped at {PASS_THRESHOLD - 1}: "
                f"incident report is a required deliverable that is missing"
            )

        score = min(score, 100)  # Ensure score never exceeds 100
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
