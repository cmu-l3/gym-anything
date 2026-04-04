#!/usr/bin/env python3
"""Verifier for group_fim_active_response task.

A security architect must configure Wazuh for HIPAA-compliant critical server monitoring
with FIM and automated response capabilities.

Scoring (100 points total):
- Agent group 'critical-servers' exists in Wazuh: 20 pts
- Agent 000 assigned to 'critical-servers' group: 20 pts
- Group agent.conf has syscheck/FIM for critical paths: 25 pts
- Custom detection rule for critical file modifications (level >= 10): 20 pts
- Active response configured in ossec.conf: 15 pts

Pass threshold: 70 points
Wrong-target check: if none of the criteria reference the 'critical-servers' group, score=0
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_group_fim_active_response(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/group_fim_active_response_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # GATE: Wrong target check — if agent created a different group, flag it
        group_exists = result.get('group_exists', False)
        if not group_exists:
            # Check if maybe agent just forgot to name it correctly (agent 000 in group but group not found)
            if not result.get('agent_000_in_group', False):
                feedback_parts.append(
                    "FAIL: Group 'critical-servers' not found and agent 000 not in it. "
                    "Ensure the group is named exactly 'critical-servers'."
                )

        # Criterion 1: Group 'critical-servers' exists (20 pts)
        if group_exists:
            score += 20
            subscores['group_created'] = True
            feedback_parts.append("Agent group 'critical-servers' created successfully")
        else:
            subscores['group_created'] = False
            feedback_parts.append("FAIL: Agent group 'critical-servers' not found in Wazuh")

        # Criterion 2: Agent 000 assigned to critical-servers (20 pts)
        if result.get('agent_000_in_group'):
            score += 20
            subscores['agent_assigned'] = True
            feedback_parts.append(
                f"Wazuh manager agent (000) assigned to 'critical-servers' group"
            )
        else:
            subscores['agent_assigned'] = False
            current_groups = result.get('agent_000_groups', 'unknown')
            feedback_parts.append(
                f"FAIL: Agent 000 not in 'critical-servers' (current groups: {current_groups})"
            )

        # Criterion 3: FIM configured in group agent.conf (25 pts)
        if result.get('fim_configured_in_group'):
            score += 25
            subscores['fim_configured'] = True
            paths = result.get('fim_paths_found', '')
            feedback_parts.append(
                f"FIM (syscheck) configured in critical-servers agent.conf for paths: {paths}"
            )
        else:
            subscores['fim_configured'] = False
            feedback_parts.append(
                "FAIL: FIM (syscheck/directories) not configured in critical-servers agent.conf "
                "for /etc/passwd, /etc/shadow, /etc/ssh/, /etc/audit/"
            )

        # Criterion 4: Custom rule for critical file modifications at level >= 10 (20 pts)
        fim_rule_level = int(result.get('fim_rule_level', 0))
        if result.get('fim_rule_exists') and fim_rule_level >= 10:
            score += 20
            subscores['fim_rule'] = True
            extra = " (meets level 12 requirement)" if fim_rule_level >= 12 else " (partially meets level 12 requirement)"
            feedback_parts.append(f"Custom FIM detection rule created at level {fim_rule_level}{extra}")
        elif result.get('fim_rule_exists'):
            score += 8
            subscores['fim_rule'] = False
            feedback_parts.append(
                f"FIM rule found but level {fim_rule_level} is below required level 10 (partial credit)"
            )
        else:
            subscores['fim_rule'] = False
            feedback_parts.append(
                "FAIL: No custom rule found detecting critical file modifications "
                "(FIM/syscheck events on /etc/passwd, /etc/shadow, etc.)"
            )

        # Criterion 5: Active response configured (15 pts)
        if result.get('active_response_configured'):
            score += 15
            subscores['active_response'] = True
            feedback_parts.append("Active response configured in Wazuh ossec.conf")
        else:
            subscores['active_response'] = False
            feedback_parts.append(
                "FAIL: No active response configuration found "
                "(check Management > Configuration > Active Response in Wazuh dashboard)"
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
