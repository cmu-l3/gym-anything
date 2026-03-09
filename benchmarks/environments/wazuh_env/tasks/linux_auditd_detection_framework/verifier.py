#!/usr/bin/env python3
"""Verifier for linux_auditd_detection_framework task.

A Security Engineer must build a complete Linux auditd monitoring pipeline in Wazuh:
parent+child decoder chain, threat-category detection rules with MITRE mappings,
CDB lookup list of high-risk executables, and ossec.conf monitoring configuration.

Scoring (100 points total):
- Auditd decoder chain (parent + child decoders): 20 pts
- >=2 detection rules covering distinct threat categories: 25 pts
- >=1 rule with MITRE ATT&CK technique mapping: 15 pts
- CDB list with >=3 high-risk executable paths: 20 pts
- ossec.conf configured to monitor /var/log/audit/audit.log: 20 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_linux_auditd_detection_framework(traj, env_info, task_info):
    """Verify linux_auditd_detection_framework task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/linux_auditd_detection_framework_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Auditd decoder chain (parent + child) (20 pts)
        audit_decoder = bool(result.get('audit_decoder_found'))
        audit_child = bool(result.get('audit_child_decoder_found'))
        audit_dec_count = int(result.get('audit_decoder_count', 0))

        if audit_decoder and audit_child:
            score += 20
            subscores['decoder_chain'] = True
            feedback_parts.append(f"Auditd parent+child decoder chain ({audit_dec_count} decoders) (20/20)")
        elif audit_decoder:
            score += 10
            subscores['decoder_chain'] = False
            feedback_parts.append("Auditd parent decoder found but no child decoder (10/20)")
        else:
            subscores['decoder_chain'] = False
            feedback_parts.append("No auditd decoder found in local_decoder.xml (0/20)")

        # Criterion 2: >=2 detection rules covering distinct threat categories (25 pts)
        total_rules = int(result.get('total_auditd_rules', 0))
        privesc = bool(result.get('privesc_rule'))
        cred = bool(result.get('cred_access_rule'))
        exec_rule = bool(result.get('exec_rule'))
        distinct_categories = int(privesc) + int(cred) + int(exec_rule)

        if distinct_categories >= 2:
            score += 25
            subscores['threat_rules'] = True
            cats = [c for c, v in [("privilege escalation", privesc), ("credential access", cred), ("suspicious exec", exec_rule)] if v]
            feedback_parts.append(f"Detection rules for {distinct_categories} threat categories: {', '.join(cats)} (25/25)")
        elif distinct_categories == 1 or total_rules >= 1:
            score += 10
            subscores['threat_rules'] = False
            feedback_parts.append(f"Only {distinct_categories} distinct threat category covered; need >=2 (10/25)")
        else:
            subscores['threat_rules'] = False
            feedback_parts.append("No auditd-based detection rules found (0/25)")

        # Criterion 3: MITRE ATT&CK technique mapping (15 pts)
        mitre_found = bool(result.get('mitre_found'))
        if mitre_found:
            score += 15
            subscores['mitre'] = True
            feedback_parts.append("MITRE ATT&CK technique mapping found in rules (15/15)")
        else:
            subscores['mitre'] = False
            feedback_parts.append("No MITRE ATT&CK mapping (<mitre><id>Txxxx</id></mitre>) in rules (0/15)")

        # Criterion 4: CDB list with >=3 high-risk executable paths (20 pts)
        cdb_found = bool(result.get('cdb_list_found'))
        cdb_entries = int(result.get('cdb_entry_count', 0))
        if cdb_found and cdb_entries >= 3:
            score += 20
            subscores['cdb_list'] = True
            feedback_parts.append(f"CDB executable list with {cdb_entries} entries (20/20)")
        elif cdb_found and cdb_entries >= 1:
            score += 10
            subscores['cdb_list'] = False
            feedback_parts.append(f"CDB list found but only {cdb_entries} entries (need >=3) (10/20)")
        else:
            subscores['cdb_list'] = False
            feedback_parts.append("No CDB list with executable paths found in /var/ossec/etc/lists/ (0/20)")

        # Criterion 5: ossec.conf monitoring audit.log (20 pts)
        audit_monitored = bool(result.get('audit_log_monitored'))
        if audit_monitored:
            score += 20
            subscores['ossec_conf'] = True
            feedback_parts.append("ossec.conf monitors /var/log/audit/audit.log (20/20)")
        else:
            subscores['ossec_conf'] = False
            feedback_parts.append("ossec.conf not updated to monitor audit.log (0/20)")

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
        logger.exception("Verification error in linux_auditd_detection_framework")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
