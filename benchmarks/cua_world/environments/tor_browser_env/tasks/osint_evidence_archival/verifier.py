#!/usr/bin/env python3
"""Verifier for osint_evidence_archival task.

Verifies that the agent properly archived 3 Tor Project pages as PDFs
and created an organized evidence log in the target directory.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "osint_evidence_archival"

def verify_osint_evidence_archival(traj, env_info, task_info):
    """
    Scoring system (100 points total):
    - `evidence_01_tor_check.pdf` exists and valid: 15 pts
    - `evidence_02_tor_history.pdf` exists and valid: 15 pts
    - `evidence_03_tor_metrics.pdf` exists and valid: 15 pts
    - All 3 PDFs created after task start: 10 pts
    - `evidence_log.txt` exists: 10 pts
    - Log contains all 3 URLs: 15 pts
    - Log references all 3 PDF filenames: 10 pts
    - check.torproject.org in history: 4 pts
    - torproject.org/about/history in history: 3 pts
    - metrics.torproject.org in history: 3 pts

    Pass Threshold: 60 points AND at least 2 valid PDFs exist.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env(f"/tmp/{TASK_NAME}_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Result file not found or invalid JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    logger.info(f"Result Data: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []
    pdfs = result.get('pdfs', {})
    log_data = result.get('log_file', {})
    history_data = result.get('history', {})
    
    valid_pdf_count = 0
    new_pdf_count = 0

    # 1. PDF 1: evidence_01_tor_check.pdf (15 pts)
    pdf1 = pdfs.get("evidence_01_tor_check.pdf", {})
    if pdf1.get("exists") and pdf1.get("valid"):
        score += 15
        valid_pdf_count += 1
        feedback_parts.append("PDF 1 valid (15/15)")
    elif pdf1.get("exists"):
        score += 5
        feedback_parts.append("PDF 1 exists but invalid size/header (5/15)")
    else:
        feedback_parts.append("PDF 1 missing (0/15)")

    if pdf1.get("new"): new_pdf_count += 1

    # 2. PDF 2: evidence_02_tor_history.pdf (15 pts)
    pdf2 = pdfs.get("evidence_02_tor_history.pdf", {})
    if pdf2.get("exists") and pdf2.get("valid"):
        score += 15
        valid_pdf_count += 1
        feedback_parts.append("PDF 2 valid (15/15)")
    elif pdf2.get("exists"):
        score += 5
        feedback_parts.append("PDF 2 exists but invalid size/header (5/15)")
    else:
        feedback_parts.append("PDF 2 missing (0/15)")

    if pdf2.get("new"): new_pdf_count += 1

    # 3. PDF 3: evidence_03_tor_metrics.pdf (15 pts)
    pdf3 = pdfs.get("evidence_03_tor_metrics.pdf", {})
    if pdf3.get("exists") and pdf3.get("valid"):
        score += 15
        valid_pdf_count += 1
        feedback_parts.append("PDF 3 valid (15/15)")
    elif pdf3.get("exists"):
        score += 5
        feedback_parts.append("PDF 3 exists but invalid size/header (5/15)")
    else:
        feedback_parts.append("PDF 3 missing (0/15)")

    if pdf3.get("new"): new_pdf_count += 1

    # 4. Anti-gaming check: Were the PDFs created during the task? (10 pts)
    if new_pdf_count == 3:
        score += 10
        feedback_parts.append("All PDFs created during task (10/10)")
    elif new_pdf_count > 0:
        score += 5
        feedback_parts.append(f"Some PDFs created during task ({new_pdf_count}/3) (5/10)")
    else:
        feedback_parts.append("No PDFs created during task duration (0/10)")

    # 5. Evidence Log Exists (10 pts)
    if log_data.get("exists"):
        score += 10
        feedback_parts.append("Evidence log exists (10/10)")
    else:
        feedback_parts.append("Evidence log missing (0/10)")

    # 6. Log contains all 3 URLs (15 pts)
    urls_found = sum([
        log_data.get("contains_check_url", False),
        log_data.get("contains_history_url", False),
        log_data.get("contains_metrics_url", False)
    ])
    if urls_found == 3:
        score += 15
        feedback_parts.append("Log contains all 3 URLs (15/15)")
    else:
        pts = urls_found * 5
        score += pts
        feedback_parts.append(f"Log contains {urls_found}/3 URLs ({pts}/15)")

    # 7. Log references all 3 PDF filenames (10 pts)
    pdfs_found = sum([
        log_data.get("contains_check_pdf", False),
        log_data.get("contains_history_pdf", False),
        log_data.get("contains_metrics_pdf", False)
    ])
    if pdfs_found == 3:
        score += 10
        feedback_parts.append("Log references all 3 PDFs (10/10)")
    else:
        pts = pdfs_found * 3
        score += pts
        feedback_parts.append(f"Log references {pdfs_found}/3 PDFs ({pts}/10)")

    # 8-10. Browser History Checks (10 pts total)
    if history_data.get("visited_check"):
        score += 4
        feedback_parts.append("History: check.torproject.org (4/4)")
    else:
        feedback_parts.append("History: check missing (0/4)")

    if history_data.get("visited_history"):
        score += 3
        feedback_parts.append("History: about/history (3/3)")
    else:
        feedback_parts.append("History: about/history missing (0/3)")

    if history_data.get("visited_metrics"):
        score += 3
        feedback_parts.append("History: metrics (3/3)")
    else:
        feedback_parts.append("History: metrics missing (0/3)")

    # Gate: >= 60 points AND at least 2 valid PDFs exist
    passed = (score >= 60) and (valid_pdf_count >= 2)

    feedback = " | ".join(feedback_parts)
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback
    }