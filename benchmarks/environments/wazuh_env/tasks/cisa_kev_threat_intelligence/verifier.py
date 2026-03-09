#!/usr/bin/env python3
"""Verifier for cisa_kev_threat_intelligence task.

A Threat Intelligence Engineer must integrate the real CISA Known Exploited Vulnerabilities
(KEV) catalog into Wazuh: CDB list with CVE IDs, detection rule using CDB lookup,
vulnerability detection module, and a written integration report.

Scoring (100 points total):
- CDB list with >=10 CVE IDs from the CISA KEV catalog: 30 pts
- >=1 detection rule using CDB list lookup (<list> element): 25 pts
- Vulnerability detection module enabled/configured in ossec.conf: 20 pts
- Integration report >=600 chars with CISA KEV references, created after task start: 25 pts

Pass threshold: 65 points
Score cap: If report missing and score >= 65, cap at 64 (required deliverable)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65


def verify_cisa_kev_threat_intelligence(traj, env_info, task_info):
    """Verify CISA KEV threat intelligence integration task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/cisa_kev_threat_intelligence_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: CDB list with >=10 CVE IDs (30 pts)
        cdb_found = bool(result.get('cdb_cve_found'))
        cdb_count = int(result.get('cdb_cve_count', 0))

        if cdb_found and cdb_count >= 10:
            score += 30
            subscores['cdb_list'] = True
            feedback_parts.append(f"CDB list with {cdb_count} CISA KEV CVE entries (30/30)")
        elif cdb_found and cdb_count >= 5:
            score += 18
            subscores['cdb_list'] = False
            feedback_parts.append(f"CDB list found but only {cdb_count} CVE entries (need >=10) (18/30)")
        elif cdb_found and cdb_count >= 1:
            score += 8
            subscores['cdb_list'] = False
            feedback_parts.append(f"CDB list found with {cdb_count} CVE entries (need >=10) (8/30)")
        else:
            subscores['cdb_list'] = False
            feedback_parts.append(
                "No CDB list with CVE-format entries found in /var/ossec/etc/lists/ (0/30)"
            )

        # Criterion 2: Detection rule with CDB lookup (<list> element) (25 pts)
        rule_with_list = bool(result.get('rule_with_cdb_lookup'))
        rule_refs_kev = bool(result.get('cdb_rule_references_kev'))
        new_rules = int(result.get('new_rule_count', 0))

        if rule_with_list and rule_refs_kev:
            score += 25
            subscores['cdb_rule'] = True
            feedback_parts.append("Detection rule with CDB lookup referencing KEV list (25/25)")
        elif rule_with_list:
            score += 15
            subscores['cdb_rule'] = False
            feedback_parts.append(
                "Rule with <list> element found but may not reference the KEV CDB list (15/25)"
            )
        elif new_rules >= 1:
            score += 5
            subscores['cdb_rule'] = False
            feedback_parts.append(
                f"{new_rules} new rule(s) added but none use CDB list lookup <list> element (5/25)"
            )
        else:
            subscores['cdb_rule'] = False
            feedback_parts.append("No detection rule using CDB list lookup (<list> element) found (0/25)")

        # Criterion 3: Vulnerability detection module configured (20 pts)
        vuln_enabled = bool(result.get('vuln_detector_enabled'))
        vuln_wodle = bool(result.get('vuln_detector_wodle'))
        syscollector = bool(result.get('syscollector_enabled'))
        newly_conf = bool(result.get('vuln_detector_newly_configured'))
        initial_vuln = bool(result.get('initial_vuln_detector'))

        if vuln_wodle or (vuln_enabled and not initial_vuln):
            # Agent explicitly configured the vulnerability detector
            score += 20
            subscores['vuln_detector'] = True
            feedback_parts.append("Vulnerability detection module configured in ossec.conf (20/20)")
        elif vuln_enabled and syscollector:
            # Was already there but agent verified/referenced it
            score += 15
            subscores['vuln_detector'] = False
            feedback_parts.append(
                "Vulnerability detection present (syscollector + detector) but may be pre-existing (15/20)"
            )
        elif vuln_enabled or syscollector:
            score += 8
            subscores['vuln_detector'] = False
            feedback_parts.append(
                "Partial vulnerability detection config found (8/20)"
            )
        else:
            subscores['vuln_detector'] = False
            feedback_parts.append(
                "Vulnerability detection module not found in ossec.conf (0/20)"
            )

        # Criterion 4: Integration report (25 pts)
        report_exists = bool(result.get('report_exists'))
        report_size = int(result.get('report_size', 0))
        report_after = bool(result.get('report_after_start'))
        report_cisa = bool(result.get('report_has_cisa_reference'))
        report_cve = bool(result.get('report_has_cve_content'))

        report_quality = int(report_cisa) + int(report_cve)

        if report_exists and report_size >= 600 and report_after and report_quality >= 2:
            score += 25
            subscores['integration_report'] = True
            feedback_parts.append(
                f"Integration report: {report_size} chars with CISA KEV content (25/25)"
            )
        elif report_exists and report_size >= 600 and report_after:
            score += 15
            subscores['integration_report'] = False
            feedback_parts.append(
                f"Report ({report_size} chars) exists but lacks CISA/CVE-specific content (15/25)"
            )
        elif report_exists and report_size >= 600:
            score += 10
            subscores['integration_report'] = False
            feedback_parts.append(
                f"Report ({report_size} chars) may be pre-existing (not created after task start) (10/25)"
            )
        elif report_exists:
            score += 3
            subscores['integration_report'] = False
            feedback_parts.append(f"Report too short: {report_size} < 600 chars required (3/25)")
        else:
            subscores['integration_report'] = False
            feedback_parts.append("No report at /home/ga/Desktop/kev_integration_report.txt (0/25)")

        # Score cap: report is a required deliverable
        if not subscores.get('integration_report') and score >= PASS_THRESHOLD:
            score = PASS_THRESHOLD - 1
            feedback_parts.append(
                f"Score capped at {PASS_THRESHOLD - 1}: integration report is a required deliverable"
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
        logger.exception("Verification error in cisa_kev_threat_intelligence")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
