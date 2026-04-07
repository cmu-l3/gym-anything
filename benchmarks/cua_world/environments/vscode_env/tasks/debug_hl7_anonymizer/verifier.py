#!/usr/bin/env python3
"""
Verifier for the debug_hl7_anonymizer task.

Evaluates 5 specific bug fixes in the Node.js ETL pipeline.
Scores 20 points per fix. Pass threshold is 60 points, BUT the 
PHI Redaction bug MUST be fixed to pass (security/privacy requirement).
"""

import os
import sys
import json
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_hl7_anonymizer(traj, env_info, task_info):
    """
    Verify that the 5 bugs in the HL7 anonymizer have been fixed.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='hl7_verify_')
    local_result = os.path.join(temp_dir, "hl7_anonymizer_result.json")

    try:
        copy_from_env("/tmp/hl7_anonymizer_result.json", local_result)
        with open(local_result, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    eval_behavior = result_data.get("eval_behavior", {})
    source_files = result_data.get("source_files", {})
    
    score = 0
    feedback = []

    # ──────────────────────────────────────────────────────────
    # BUG 1: PHI Redaction (anonymizer.js) - MANDATORY
    # ──────────────────────────────────────────────────────────
    phi_passed = eval_behavior.get("phi_redacted", False)
    anon_src = source_files.get("src/anonymizer.js", "")
    
    # Fallback to regex if behavioral check crashed
    if not phi_passed and anon_src:
        if "delete" in anon_src and "address" in anon_src and "phone" in anon_src:
            phi_passed = True
            
    if phi_passed:
        score += 20
        feedback.append("[+] Bug 1: PHI redaction fixed (Address and Phone removed).")
    else:
        feedback.append("[-] Bug 1: PHI redaction FAILED. Address/phone leak detected.")

    # ──────────────────────────────────────────────────────────
    # BUG 2: 0-indexed JS Date (utils/dateFormatter.js)
    # ──────────────────────────────────────────────────────────
    date_passed = eval_behavior.get("date_fixed", False)
    date_src = source_files.get("src/utils/dateFormatter.js", "")
    
    if not date_passed and date_src:
        if "- 1" in date_src or "+ 1" in date_src or "moment(" in date_src or "date-fns" in date_src:
            date_passed = True

    if date_passed:
        score += 20
        feedback.append("[+] Bug 2: Date 0-indexing fixed.")
    else:
        feedback.append("[-] Bug 2: Date shifting is mathematically incorrect (0-index bug remains).")

    # ──────────────────────────────────────────────────────────
    # BUG 3: AL1 missing segment crash (parser.js)
    # ──────────────────────────────────────────────────────────
    al1_passed = eval_behavior.get("al1_crash_fixed", False)
    parser_src = source_files.get("src/parser.js", "")
    
    if not al1_passed and parser_src:
        if "if (al1Seg)" in parser_src.replace(" ", "") or "al1Seg?" in parser_src or "if(al1Seg)" in parser_src.replace(" ", ""):
            al1_passed = True

    if al1_passed:
        score += 20
        feedback.append("[+] Bug 3: AL1 missing segment handled correctly (no crash).")
    else:
        feedback.append("[-] Bug 3: Parser still crashes when AL1 segment is missing.")

    # ──────────────────────────────────────────────────────────
    # BUG 4: OBX find -> filter (parser.js)
    # ──────────────────────────────────────────────────────────
    obx_passed = eval_behavior.get("obx_filter_fixed", False)
    
    if not obx_passed and parser_src:
        if "filter(" in parser_src and "OBX" in parser_src:
            obx_passed = True

    if obx_passed:
        score += 20
        feedback.append("[+] Bug 4: Multiple OBX segments extracted properly (filter used).")
    else:
        feedback.append("[-] Bug 4: Labs extraction still drops subsequent OBX segments (find used).")

    # ──────────────────────────────────────────────────────────
    # BUG 5: Async control flow inside forEach (index.js)
    # ──────────────────────────────────────────────────────────
    async_passed = False
    index_src = source_files.get("src/index.js", "")
    
    if index_src:
        has_foreach_async = bool(re.search(r'forEach\s*\(\s*async', index_src))
        has_for_of = bool(re.search(r'for\s*\(\s*(const|let|var)\s+\w+\s+of\s+files\s*\)', index_src))
        has_promise_all = bool(re.search(r'Promise\.all', index_src))
        has_standard_for = bool(re.search(r'for\s*\(\s*let\s+i\s*=', index_src))
        
        if (has_for_of or has_promise_all or has_standard_for) and not has_foreach_async:
            async_passed = True

    if async_passed:
        score += 20
        feedback.append("[+] Bug 5: Async file loop control flow fixed.")
    else:
        feedback.append("[-] Bug 5: index.js still uses files.forEach(async ...), writing prematurely.")

    # ──────────────────────────────────────────────────────────
    # Final Evaluation
    # ──────────────────────────────────────────────────────────
    # Required passing conditions
    passed = (score >= 60) and phi_passed

    if not phi_passed and score >= 60:
        feedback.append("CRITICAL: Final grade is FAIL because PHI Redaction (Security) check was not met.")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }