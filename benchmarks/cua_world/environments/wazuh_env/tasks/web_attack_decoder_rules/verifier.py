#!/usr/bin/env python3
"""Verifier for web_attack_decoder_rules task.

A SOC analyst must create custom Wazuh decoders and detection rules for
web application attack detection from nginx access logs.

Scoring (100 points total):
- Custom nginx/web decoder exists in local_decoder.xml: 20 pts
- At least 3 web attack detection rules created: 30 pts
- At least one rule has severity level >= 10: 20 pts
- At least one rule has MITRE ATT&CK technique mapping: 15 pts
- local_decoder.xml is valid XML: 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_web_attack_decoder_rules(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/web_attack_decoder_rules_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Custom nginx/web decoder exists (20 pts)
        if result.get('decoder_exists'):
            score += 20
            subscores['decoder'] = True
            name = result.get('decoder_name', 'unknown')
            feedback_parts.append(f"Custom web/nginx log decoder created: '{name}'")
        else:
            subscores['decoder'] = False
            feedback_parts.append(
                "FAIL: No web/nginx-related decoder found in local_decoder.xml "
                "(decoder name or program_name should reference nginx/http/apache/web)"
            )

        # Criterion 2: At least 3 distinct web attack detection rules (30 pts)
        rule_count = int(result.get('web_attack_rule_count', 0))
        if rule_count >= 3:
            score += 30
            subscores['rule_coverage'] = True
            sql_lvl = int(result.get('sql_injection_rule_level', 0))
            trav_lvl = int(result.get('traversal_rule_level', 0))
            cmd_lvl = int(result.get('cmd_injection_rule_level', 0))
            feedback_parts.append(
                f"Created {rule_count} web attack detection rules "
                f"(SQL inj: level {sql_lvl}, traversal: level {trav_lvl}, cmd inj: level {cmd_lvl})"
            )
        elif rule_count == 2:
            score += 15
            subscores['rule_coverage'] = False
            feedback_parts.append(
                f"Only {rule_count} web attack rules found — need 3 covering SQL injection, "
                f"path traversal, and command injection"
            )
        elif rule_count == 1:
            score += 8
            subscores['rule_coverage'] = False
            feedback_parts.append(
                f"Only {rule_count} web attack rule found — need 3 distinct attack categories"
            )
        else:
            subscores['rule_coverage'] = False
            feedback_parts.append(
                "FAIL: No web attack detection rules found in local_rules.xml "
                "(expected rules detecting SQL injection, path traversal, command injection)"
            )

        # Criterion 3: At least one rule has level >= 10 (20 pts)
        max_level = int(result.get('max_rule_level', 0))
        if max_level >= 10:
            score += 20
            subscores['severity'] = True
            feedback_parts.append(
                f"Web attack rules have appropriate severity (max level {max_level} >= 10)"
            )
        elif max_level >= 8:
            score += 10
            subscores['severity'] = False
            feedback_parts.append(
                f"Rules exist but max severity {max_level} is below recommended level 10 "
                f"(SQL injection and path traversal should be level 10+)"
            )
        else:
            subscores['severity'] = False
            feedback_parts.append(
                f"FAIL: Rules have insufficient severity (max level {max_level}, "
                f"SQL injection/traversal require >= 10)"
            )

        # Criterion 4: MITRE ATT&CK technique mapping (15 pts)
        if result.get('has_mitre_mapping'):
            score += 15
            subscores['mitre'] = True
            feedback_parts.append("Rules include MITRE ATT&CK technique mapping (T1190, T1059, etc.)")
        else:
            subscores['mitre'] = False
            feedback_parts.append(
                "FAIL: No MITRE ATT&CK mapping found — add <mitre><id>T1190</id></mitre> "
                "or mitre_att&ck group to at least one rule"
            )

        # Criterion 5: Decoder XML is valid (15 pts)
        # Only relevant when a web decoder was actually created
        if result.get('decoder_exists') and result.get('decoder_xml_valid'):
            score += 15
            subscores['xml_valid'] = True
            feedback_parts.append("local_decoder.xml parses as valid XML")
        elif result.get('decoder_exists') and not result.get('decoder_xml_valid'):
            subscores['xml_valid'] = False
            feedback_parts.append(
                "FAIL: local_decoder.xml fails XML validation — check decoder syntax"
            )
        else:
            subscores['xml_valid'] = False
            # No decoder found — XML validity irrelevant

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
