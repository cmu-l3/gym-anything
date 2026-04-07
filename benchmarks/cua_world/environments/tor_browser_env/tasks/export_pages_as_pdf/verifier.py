#!/usr/bin/env python3
"""Verifier for export_pages_as_pdf task.

Checks that the agent successfully exported three Tor Project web pages
as PDF documents to the /home/ga/Documents/ directory with correct names.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_export_pages_as_pdf(traj, env_info, task_info):
    """
    Scoring Breakdown (100 pts total):
    1. tor_history.pdf exists and is valid (15 pts) [REQUIRED]
    2. tor_history.pdf created after task start (5 pts)
    3. tor_support_about.pdf exists and is valid (15 pts)
    4. tor_support_about.pdf created after task start (5 pts)
    5. tor_training_risks.pdf exists and is valid (15 pts)
    6. tor_training_risks.pdf created after task start (5 pts)
    7. History contains visits to the 3 target URLs (10 pts each = 30 pts)
    8. All 3 PDFs have distinct MD5 hashes (10 pts)

    Pass threshold: 60+ points AND tor_history.pdf exists as valid PDF (gate)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
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
    task_start_ts = result.get('task_start_timestamp', 0)

    f_history = result.get('file_history', {})
    f_support = result.get('file_support', {})
    f_risks = result.get('file_risks', {})
    history = result.get('history', {})

    # Criterion 1 & 2: tor_history.pdf
    if f_history.get('exists') and f_history.get('valid_pdf'):
        score += 15
        feedback_parts.append("tor_history.pdf exists and is valid PDF (15/15)")
        if f_history.get('mtime', 0) > task_start_ts:
            score += 5
            feedback_parts.append("tor_history.pdf is newly created (5/5)")
        else:
            feedback_parts.append("tor_history.pdf predates task start (0/5)")
    else:
        feedback_parts.append("tor_history.pdf missing or invalid (0/20)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts), "details": "tor_history.pdf gate failed"}

    # Criterion 3 & 4: tor_support_about.pdf
    if f_support.get('exists') and f_support.get('valid_pdf'):
        score += 15
        feedback_parts.append("tor_support_about.pdf exists and is valid PDF (15/15)")
        if f_support.get('mtime', 0) > task_start_ts:
            score += 5
            feedback_parts.append("tor_support_about.pdf is newly created (5/5)")
        else:
            feedback_parts.append("tor_support_about.pdf predates task start (0/5)")
    else:
        feedback_parts.append("tor_support_about.pdf missing or invalid (0/20)")

    # Criterion 5 & 6: tor_training_risks.pdf
    if f_risks.get('exists') and f_risks.get('valid_pdf'):
        score += 15
        feedback_parts.append("tor_training_risks.pdf exists and is valid PDF (15/15)")
        if f_risks.get('mtime', 0) > task_start_ts:
            score += 5
            feedback_parts.append("tor_training_risks.pdf is newly created (5/5)")
        else:
            feedback_parts.append("tor_training_risks.pdf predates task start (0/5)")
    else:
        feedback_parts.append("tor_training_risks.pdf missing or invalid (0/20)")

    # Criterion 7: Browser History
    if history.get('history_history_page'):
        score += 10
        feedback_parts.append("Visited torproject.org/about/history (10/10)")
    else:
        feedback_parts.append("History page visit not found (0/10)")

    if history.get('history_support_page'):
        score += 10
        feedback_parts.append("Visited support.torproject.org/about (10/10)")
    else:
        feedback_parts.append("Support page visit not found (0/10)")

    if history.get('history_risks_page'):
        score += 10
        feedback_parts.append("Visited community.torproject.org/training/risks (10/10)")
    else:
        feedback_parts.append("Risks page visit not found (0/10)")

    # Criterion 8: MD5 uniqueness
    md5_list = [f.get('md5') for f in [f_history, f_support, f_risks] if f.get('exists') and f.get('valid_pdf') and f.get('md5')]
    if len(md5_list) == 3 and len(set(md5_list)) == 3:
        score += 10
        feedback_parts.append("All PDFs have distinct content (10/10)")
    elif len(md5_list) == 3:
        feedback_parts.append("Some PDFs have identical content - potential duplicate exports (0/10)")
    else:
        feedback_parts.append("Could not verify uniqueness of all 3 PDFs (0/10)")

    # Pass requirement
    passed = score >= 60

    logger.info(f"Final Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }