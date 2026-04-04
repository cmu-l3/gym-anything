#!/usr/bin/env python3
"""Verifier for multi_circuit_threat_intelligence task.

A threat intelligence analyst researches two separate threat topics with circuit isolation
(New Identity between sessions). Verifies both research threads were conducted independently.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "multi_circuit_threat_intelligence"


def verify_multi_circuit_threat_intelligence(traj, env_info, task_info):
    """
    Scoring (100 points):

    Thread 1 — Ransomware:
    1. History has check.torproject.org visit                  - 10 pts
    2. History has DuckDuckGo onion ransomware search          - 10 pts
    3. Folder 'Threat Intel - Ransomware' exists               - 15 pts  [REQUIRED]
    4. Bookmark in 'Threat Intel - Ransomware' folder          - 10 pts
    5. ransomware_research_notes.txt exists and is non-empty   - 10 pts

    New Identity (evidence):
    6. check.torproject.org visited 2+ times (pre and post NI) - 10 pts

    Thread 2 — Phishing:
    7. History has DuckDuckGo onion phishing search            - 10 pts
    8. Folder 'Threat Intel - Phishing' exists                 - 15 pts  [REQUIRED]
    9. Bookmark in 'Threat Intel - Phishing' folder            - 5 pts
    10. phishing_research_notes.txt exists and is non-empty    - 5 pts

    Pass: 60+ points AND both required folders exist
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

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

    if not result.get('db_found', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Tor Browser places.sqlite not found — browser not used"
        }

    score = 0
    feedback_parts = []

    # Criterion 1: History has check.torproject.org
    if result.get('history_has_check_torproject', False):
        score += 10
        feedback_parts.append("Visited check.torproject.org (10/10)")
    else:
        feedback_parts.append("check.torproject.org NOT in history (0/10)")

    # Criterion 2: DuckDuckGo onion ransomware search
    if result.get('history_has_ddg_ransomware_search', False):
        score += 10
        feedback_parts.append("DuckDuckGo ransomware search in history (10/10)")
    elif result.get('history_has_ddg_onion', False):
        score += 5
        feedback_parts.append("DuckDuckGo onion visited but no ransomware search found (5/10)")
    else:
        feedback_parts.append("No DuckDuckGo onion visit found (0/10)")

    # Criterion 3: Folder 'Threat Intel - Ransomware' [REQUIRED]
    folder_ransomware = result.get('folder_ransomware', False)
    if folder_ransomware:
        score += 15
        feedback_parts.append("Folder 'Threat Intel - Ransomware' created (15/15)")
    else:
        feedback_parts.append("Folder 'Threat Intel - Ransomware' NOT found (0/15)")

    # Criterion 4: Bookmark in ransomware folder
    if result.get('bookmark_in_ransomware_folder', False):
        score += 10
        feedback_parts.append("Bookmark in 'Threat Intel - Ransomware' (10/10)")
    else:
        feedback_parts.append("No bookmark in 'Threat Intel - Ransomware' (0/10)")

    # Criterion 5: ransomware_research_notes.txt exists and non-empty
    f1_exists = result.get('file1_exists', False)
    f1_new = result.get('file1_is_new', False)
    f1_size = result.get('file1_size', 0)
    if f1_exists and f1_new and f1_size > 10:
        score += 10
        feedback_parts.append(f"ransomware_research_notes.txt created ({f1_size}B) (10/10)")
    elif f1_exists and f1_size > 0:
        score += 5
        feedback_parts.append(f"ransomware_research_notes.txt exists but may be stale (5/10)")
    else:
        feedback_parts.append("ransomware_research_notes.txt NOT found or empty (0/10)")

    # Criterion 6: New Identity evidence (2+ visits to check.torproject.org)
    tor_visit_count = result.get('check_torproject_visit_count', 0)
    if tor_visit_count >= 2:
        score += 10
        feedback_parts.append(f"check.torproject.org visited {tor_visit_count}x — New Identity used (10/10)")
    elif tor_visit_count == 1:
        score += 3
        feedback_parts.append("check.torproject.org visited only once — New Identity may not have been used (3/10)")
    else:
        feedback_parts.append("check.torproject.org not visited (0/10)")

    # Criterion 7: DuckDuckGo onion phishing search
    if result.get('history_has_ddg_phishing_search', False):
        score += 10
        feedback_parts.append("DuckDuckGo phishing search in history (10/10)")
    else:
        feedback_parts.append("No DuckDuckGo onion phishing search found (0/10)")

    # Criterion 8: Folder 'Threat Intel - Phishing' [REQUIRED]
    folder_phishing = result.get('folder_phishing', False)
    if folder_phishing:
        score += 15
        feedback_parts.append("Folder 'Threat Intel - Phishing' created (15/15)")
    else:
        feedback_parts.append("Folder 'Threat Intel - Phishing' NOT found (0/15)")

    # Criterion 9: Bookmark in phishing folder
    if result.get('bookmark_in_phishing_folder', False):
        score += 5
        feedback_parts.append("Bookmark in 'Threat Intel - Phishing' (5/5)")
    else:
        feedback_parts.append("No bookmark in 'Threat Intel - Phishing' (0/5)")

    # Criterion 10: phishing_research_notes.txt
    f2_exists = result.get('file2_exists', False)
    f2_new = result.get('file2_is_new', False)
    f2_size = result.get('file2_size', 0)
    if f2_exists and f2_new and f2_size > 10:
        score += 5
        feedback_parts.append(f"phishing_research_notes.txt created ({f2_size}B) (5/5)")
    elif f2_exists and f2_size > 0:
        score += 2
        feedback_parts.append(f"phishing_research_notes.txt exists but may be stale (2/5)")
    else:
        feedback_parts.append("phishing_research_notes.txt NOT found or empty (0/5)")

    # Pass: score >= 60 AND both required folders exist
    passed = score >= 60 and folder_ransomware and folder_phishing

    feedback = " | ".join(feedback_parts)
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "subscores": {
            "history_torproject": 10 if result.get('history_has_check_torproject') else 0,
            "ddg_ransomware_search": 10 if result.get('history_has_ddg_ransomware_search') else 5 if result.get('history_has_ddg_onion') else 0,
            "folder_ransomware": 15 if folder_ransomware else 0,
            "bookmark_ransomware": 10 if result.get('bookmark_in_ransomware_folder') else 0,
            "file_ransomware": 10 if (f1_exists and f1_new and f1_size > 10) else 5 if (f1_exists and f1_size > 0) else 0,
            "new_identity_evidence": 10 if tor_visit_count >= 2 else 3 if tor_visit_count == 1 else 0,
            "ddg_phishing_search": 10 if result.get('history_has_ddg_phishing_search') else 0,
            "folder_phishing": 15 if folder_phishing else 0,
            "bookmark_phishing": 5 if result.get('bookmark_in_phishing_folder') else 0,
            "file_phishing": 5 if (f2_exists and f2_new and f2_size > 10) else 2 if (f2_exists and f2_size > 0) else 0,
        }
    }
