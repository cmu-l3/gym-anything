#!/usr/bin/env python3
"""Verifier stub for security_compliance_audit task.

Full verification is handled by vlm_checklist_verifier. This stub provides
basic programmatic scoring based on the exported result JSON.

Scoring (100 points total):
  REQ-1 Browser Hardening:
    - Security level = Safest (slider=1)        10 pts  [REQUIRED gate]
    - HTTPS-Only Mode in all windows              8 pts
    - History never saved                          7 pts
  REQ-2 Exit Geofencing:
    - torrc has ExitNodes with {ch},{is},{nl}     12 pts
    - torrc has StrictNodes 1                      5 pts
    - check.torproject.org visited (verification)  5 pts
  REQ-3 Speculative + Canvas:
    - speculative-parallel-limit = 0               4 pts
    - prefetch-next = false                        4 pts
    - dns.disablePrefetch = true                   2 pts  (already correct by default)
    - canvas_test.html visited                     5 pts
  REQ-4 Circuit Documentation:
    - Report contains valid IP address             5 pts
  Report Quality:
    - Report file exists and created during task  12 pts  [REQUIRED gate]
    - Report has all 4 REQ sections                8 pts
    - Report has Summary section                   5 pts
    - Report summary counts are present            3 pts
    - Report size > 800 bytes                      5 pts

Pass threshold: score >= 60 AND both gates met
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "security_compliance_audit"


def verify_security_compliance_audit(traj, env_info, task_info):
    """Verify the agent completed the security compliance audit."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env(f"/tmp/{TASK_NAME}_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Result file not found: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    logger.info(f"Result: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []
    subscores = {}

    # Gate: prefs file must exist
    if not result.get('prefs_file_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Tor Browser prefs.js not found"
        }

    # ─── REQ-1: Browser Hardening ───
    # Security level = Safest (REQUIRED)
    # Tor Browser v15 uses INVERTED slider values:
    #   slider=4 → Standard, slider=2 → Safer, slider=1 → Safest
    slider = result.get('security_slider', 4)
    if slider == 1:
        score += 10
        subscores["security_safest"] = 10
        feedback_parts.append("Security Safest (10/10)")
    elif slider == 2:
        score += 5
        subscores["security_safest"] = 5
        feedback_parts.append(f"Security Safer partial (5/10)")
    else:
        subscores["security_safest"] = 0
        feedback_parts.append(f"Security level={result.get('security_level','standard')} (0/10)")

    # HTTPS-Only all windows
    if result.get('https_only_all', False):
        score += 8
        subscores["https_only"] = 8
        feedback_parts.append("HTTPS-Only all windows (8/8)")
    elif result.get('https_only_private', False):
        score += 3
        subscores["https_only"] = 3
        feedback_parts.append("HTTPS-Only private-only partial (3/8)")
    else:
        subscores["https_only"] = 0
        feedback_parts.append("HTTPS-Only not enabled (0/8)")

    # History never saved
    if result.get('history_never_saved', False):
        score += 7
        subscores["history_disabled"] = 7
        feedback_parts.append("History disabled (7/7)")
    else:
        subscores["history_disabled"] = 0
        feedback_parts.append("History still enabled (0/7)")

    # ─── REQ-2: Exit Geofencing ───
    if result.get('torrc_exitnodes_all_required', False):
        score += 12
        subscores["exitnodes"] = 12
        feedback_parts.append("ExitNodes {ch},{is},{nl} (12/12)")
    elif result.get('torrc_has_exitnodes', False):
        score += 6
        subscores["exitnodes"] = 6
        feedback_parts.append(f"ExitNodes partial: {result.get('torrc_exitnodes_value','')} (6/12)")
    else:
        subscores["exitnodes"] = 0
        feedback_parts.append("No ExitNodes in torrc (0/12)")

    if result.get('torrc_has_strictnodes_1', False):
        score += 5
        subscores["strictnodes"] = 5
        feedback_parts.append("StrictNodes 1 (5/5)")
    else:
        subscores["strictnodes"] = 0
        feedback_parts.append("StrictNodes not set (0/5)")

    if result.get('history_check_torproject', False):
        score += 5
        subscores["check_torproject_visited"] = 5
        feedback_parts.append("check.torproject.org visited (5/5)")
    else:
        subscores["check_torproject_visited"] = 0
        feedback_parts.append("check.torproject.org not visited (0/5)")

    # ─── REQ-3: Speculative Connections + Canvas ───
    if result.get('speculative_parallel_limit', -1) == 0:
        score += 4
        subscores["speculative_limit"] = 4
    else:
        subscores["speculative_limit"] = 0

    if result.get('prefetch_disabled', False):
        score += 4
        subscores["prefetch"] = 4
    else:
        subscores["prefetch"] = 0

    if result.get('dns_prefetch_disabled', False):
        score += 2
        subscores["dns_prefetch"] = 2
    else:
        subscores["dns_prefetch"] = 0

    if result.get('history_canvas_test', False):
        score += 5
        subscores["canvas_tested"] = 5
        feedback_parts.append("Canvas test page visited (5/5)")
    else:
        subscores["canvas_tested"] = 0
        feedback_parts.append("Canvas test page not visited (0/5)")

    # ─── REQ-4: Circuit Documentation ───
    if result.get('report_contains_ip', False):
        score += 5
        subscores["report_has_ip"] = 5
        feedback_parts.append("Report contains IP evidence (5/5)")
    else:
        subscores["report_has_ip"] = 0
        feedback_parts.append("Report missing IP evidence (0/5)")

    # ─── Report Quality ───
    report_exists = result.get('report_exists', False)
    report_new = result.get('report_is_new', False)
    if report_exists and report_new:
        score += 12
        subscores["report_exists"] = 12
        feedback_parts.append("Report exists and new (12/12)")
    elif report_exists:
        score += 6
        subscores["report_exists"] = 6
        feedback_parts.append("Report exists but may predate task (6/12)")
    else:
        subscores["report_exists"] = 0
        feedback_parts.append("Report file missing (0/12)")

    req_sections = sum([
        result.get('report_has_req1', False),
        result.get('report_has_req2', False),
        result.get('report_has_req3', False),
        result.get('report_has_req4', False),
    ])
    section_score = min(req_sections * 2, 8)
    score += section_score
    subscores["report_sections"] = section_score
    feedback_parts.append(f"Report has {req_sections}/4 REQ sections ({section_score}/8)")

    if result.get('report_has_summary', False):
        score += 5
        subscores["report_summary"] = 5
    else:
        subscores["report_summary"] = 0

    report_content = result.get('report_content', '')
    # Check summary counts are present
    import re
    count_pattern = re.findall(r'(COMPLIANT|REMEDIATED|FAILED)\s*:\s*\d+', report_content, re.IGNORECASE)
    if len(count_pattern) >= 3:
        score += 3
        subscores["summary_counts"] = 3
    else:
        subscores["summary_counts"] = 0

    report_size = result.get('report_size', 0)
    if report_size > 800:
        score += 5
        subscores["report_size"] = 5
    elif report_size > 400:
        score += 2
        subscores["report_size"] = 2
    else:
        subscores["report_size"] = 0

    # ─── Pass determination ───
    security_gate = (slider == 1)  # Tor Browser v15: slider=1 means Safest
    report_gate = report_exists and report_new
    passed = score >= 60 and security_gate and report_gate

    feedback = " | ".join(feedback_parts)
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "subscores": subscores
    }
