#!/usr/bin/env python3
"""Verifier for ransomware_detection_playbook task.

A Security Engineer must build comprehensive ransomware detection and response capability
in Wazuh, chaining FIM, detection rules, correlation rules, active response, and a
written incident response playbook.

Scoring (100 points total):
- FIM on >=3 critical filesystem paths (ossec.conf or group agent.conf): 20 pts
- Ransomware detection rule at level >=10: 25 pts
- Frequency correlation rule (frequency + timeframe attributes): 25 pts
- Active response configured in ossec.conf: 15 pts
- Incident playbook >=600 chars, created after task start: 15 pts

Pass threshold: 65 points
Score cap: If playbook missing and score >= 65, cap at 64 (required deliverable)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65


def verify_ransomware_detection_playbook(traj, env_info, task_info):
    """Verify ransomware detection playbook task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/ransomware_detection_playbook_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: FIM on >=3 critical filesystem paths (20 pts)
        fim_count = int(result.get('fim_path_count', 0))
        if fim_count >= 3:
            score += 20
            subscores['fim'] = True
            feedback_parts.append(f"FIM on {fim_count} critical paths (20/20)")
        elif fim_count >= 1:
            score += 8
            subscores['fim'] = False
            feedback_parts.append(f"FIM partially configured: {fim_count}/3 required paths (8/20)")
        else:
            subscores['fim'] = False
            feedback_parts.append("No FIM configured on critical paths (0/20)")

        # Criterion 2: Ransomware detection rule at level >=10 (25 pts)
        ransom_found = bool(result.get('ransomware_rule_found'))
        ransom_level = int(result.get('ransomware_rule_level', 0))
        if ransom_found and ransom_level >= 10:
            score += 25
            subscores['ransom_rule'] = True
            feedback_parts.append(f"Ransomware detection rule at level {ransom_level} (25/25)")
        elif ransom_found and ransom_level >= 7:
            score += 12
            subscores['ransom_rule'] = False
            feedback_parts.append(f"Ransomware rule exists but level {ransom_level} < 10 required (12/25)")
        elif ransom_found:
            score += 5
            subscores['ransom_rule'] = False
            feedback_parts.append(f"Ransomware rule exists at low level {ransom_level} (5/25)")
        else:
            subscores['ransom_rule'] = False
            feedback_parts.append("No ransomware detection rule found (0/25)")

        # Criterion 3: Frequency correlation rule with both frequency + timeframe (25 pts)
        corr_found = bool(result.get('correlation_found'))
        corr_freq = int(result.get('correlation_frequency', 0))
        corr_timeframe = int(result.get('correlation_timeframe', 0))
        if corr_found and corr_freq >= 5 and corr_timeframe > 0:
            score += 25
            subscores['correlation'] = True
            feedback_parts.append(
                f"Correlation rule: frequency={corr_freq}, timeframe={corr_timeframe}s (25/25)"
            )
        elif corr_found and corr_freq >= 2:
            score += 12
            subscores['correlation'] = False
            if corr_freq < 5:
                feedback_parts.append(f"Correlation rule found but frequency={corr_freq} < 5 (12/25)")
            else:
                feedback_parts.append(f"Correlation rule found but missing timeframe attribute (12/25)")
        elif corr_found:
            score += 6
            subscores['correlation'] = False
            feedback_parts.append("Frequency attribute found but frequency < 2 (6/25)")
        else:
            subscores['correlation'] = False
            feedback_parts.append("No correlation rule with frequency+timeframe attributes (0/25)")

        # Criterion 4: Active response configured (15 pts)
        ar_configured = bool(result.get('ar_configured'))
        ar_count = int(result.get('ar_count', 0))
        if ar_configured:
            score += 15
            subscores['active_response'] = True
            feedback_parts.append(f"Active response configured ({ar_count} block(s)) (15/15)")
        else:
            subscores['active_response'] = False
            feedback_parts.append("No active-response block in ossec.conf (0/15)")

        # Criterion 5: Incident response playbook (15 pts)
        playbook_exists = bool(result.get('playbook_exists'))
        playbook_size = int(result.get('playbook_size', 0))
        playbook_after = bool(result.get('playbook_after_start'))
        if playbook_exists and playbook_size >= 600 and playbook_after:
            score += 15
            subscores['playbook'] = True
            feedback_parts.append(f"Incident playbook: {playbook_size} chars (15/15)")
        elif playbook_exists and playbook_size >= 600:
            score += 8
            subscores['playbook'] = False
            feedback_parts.append(
                f"Playbook ({playbook_size} chars) may be pre-existing (not created after task start) (8/15)"
            )
        elif playbook_exists:
            score += 3
            subscores['playbook'] = False
            feedback_parts.append(f"Playbook too short: {playbook_size} < 600 chars (3/15)")
        else:
            subscores['playbook'] = False
            feedback_parts.append("No playbook at /home/ga/Desktop/ransomware_playbook.txt (0/15)")

        # Score cap: playbook is a required deliverable — prevent passing without it
        if not subscores.get('playbook') and score >= PASS_THRESHOLD:
            score = PASS_THRESHOLD - 1
            feedback_parts.append(
                f"Score capped at {PASS_THRESHOLD - 1}: incident playbook is a required deliverable"
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
            "feedback": "Result file not found — export script may not have run or failed"
        }
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {e}"}
    except Exception as e:
        logger.exception("Verification error in ransomware_detection_playbook")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
