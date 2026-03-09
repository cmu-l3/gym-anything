#!/usr/bin/env python3
"""Verifier for threat_intel_cdb_rules task.

A security engineer must integrate Feodo Tracker botnet C2 IP intelligence
into Wazuh using CDB lookup lists and custom detection rules.

Scoring (100 points total):
- CDB list with >= 5 real IP entries in /var/ossec/etc/lists/: 35 pts
- At least 1 rule in local_rules.xml uses CDB list lookup (<list> element): 35 pts
- CDB-referencing rule has severity level >= 9: 20 pts
- ossec.conf explicitly declares the CDB list (ruleset/<list>): 10 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_threat_intel_cdb_rules(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/threat_intel_cdb_rules_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        feedback_parts = []

        # Criterion 1: CDB list with real IP entries (35 pts)
        # Note: Feodo Tracker feed size varies — even 1 active C2 IP is real threat intel
        if result.get('cdb_list_exists'):
            count = int(result.get('cdb_entry_count', 0))
            if count >= 1:
                score += 35
                feedback_parts.append(
                    f"CDB threat intel list created with {count} malicious C2 IP entries from Feodo Tracker"
                )
            else:
                feedback_parts.append("CDB list file found but contains no IP-format entries")
        else:
            feedback_parts.append("FAIL: No CDB list with IP entries found in /var/ossec/etc/lists/")

        # Criterion 2: Rules using CDB list lookup via <list> element (35 pts)
        rules_count = int(result.get('rules_with_cdb_lookup', 0))
        if rules_count >= 1:
            score += 35
            feedback_parts.append(
                f"Found {rules_count} detection rule(s) with CDB list lookup "
                f"(<list> element in local_rules.xml)"
            )
        else:
            feedback_parts.append(
                "FAIL: No rules found with CDB list lookup (<list> element) in local_rules.xml"
            )

        # Criterion 3: CDB rule has appropriate severity level (20 pts)
        max_level = int(result.get('max_cdb_rule_level', 0))
        if max_level >= 9:
            score += 20
            feedback_parts.append(f"CDB detection rules have appropriate severity (level {max_level} >= 9)")
        elif max_level >= 7:
            score += 10
            feedback_parts.append(
                f"CDB rules exist but severity {max_level} is below recommended level 9"
            )
        else:
            feedback_parts.append(
                f"CDB rules missing or have insufficient severity (level {max_level}, need >= 9)"
            )

        # Criterion 4: ossec.conf explicitly declares the CDB list (10 pts bonus)
        if result.get('ossec_has_list_declaration'):
            score += 10
            feedback_parts.append("ossec.conf has explicit CDB list declaration in ruleset section")

        passed = score >= PASS_THRESHOLD

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No task criteria met"
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run"
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
