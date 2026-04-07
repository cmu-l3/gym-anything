#!/usr/bin/env python3
"""
Verifier for configure_multilingual_research task.

Verifies:
1. intl.accept_languages preference modification
2. Multilingual Wikipedia and EFF visits via history
3. Creation of specific bookmark folder
4. Exact titles and correct URLs of bookmarks inside that folder.
"""

import json
import logging
import os
import tempfile
import urllib.parse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "configure_multilingual_research"


def normalize_url(url: str) -> str:
    """Helper to decode and normalize URLs for robust matching."""
    try:
        return urllib.parse.unquote(url).lower().strip()
    except:
        return url.lower().strip()


def verify_multilingual_research(traj, env_info, task_info):
    """
    Scoring logic (100 points total):
    1. intl.accept_languages contains es-ES (10 pts)
    2. intl.accept_languages contains fr-FR (10 pts)
    3. intl.accept_languages exact match 'es-ES, fr-FR, en-US' (5 pts)
    4. Spanish Wikipedia in history (10 pts)
    5. French Wikipedia in history (10 pts)
    6. EFF international page in history (5 pts)
    7. Folder "Digital Rights Research" exists (15 pts) - [GATE]
    8. Bookmark "Derechos Digitales - Wikipedia ES" in folder (10 pts)
    9. Bookmark "Droits Numériques - Wikipedia FR" in folder (10 pts)
    10. Bookmark "EFF International Issues" in folder (10 pts)
    11. All 3 bookmark URLs correct (5 pts)

    Pass threshold: 60+ points AND folder "Digital Rights Research" exists.
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
            return {"passed": False, "score": 0, "feedback": f"Result file not found or malformed: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    logger.info(f"Loaded verification data: {json.dumps(result, ensure_ascii=False)}")

    score = 0
    feedback_parts = []

    # 1-3. Check Preferences
    pref_val = result.get('accept_languages_pref', '').strip()
    pref_val_lower = pref_val.lower()

    if 'es-es' in pref_val_lower:
        score += 10
        feedback_parts.append("accept_languages includes es-ES (10/10)")
    else:
        feedback_parts.append("es-ES missing from accept_languages (0/10)")

    if 'fr-fr' in pref_val_lower:
        score += 10
        feedback_parts.append("accept_languages includes fr-FR (10/10)")
    else:
        feedback_parts.append("fr-FR missing from accept_languages (0/10)")

    if pref_val == "es-ES, fr-FR, en-US":
        score += 5
        feedback_parts.append("accept_languages exact match (5/5)")
    else:
        feedback_parts.append(f"accept_languages exact match failed: '{pref_val}' (0/5)")

    # 4-6. Check History
    history_urls = [normalize_url(h['url']) for h in result.get('history', [])]
    
    es_wiki_visited = any('es.wikipedia.org/wiki/derechos_digitales' in u for u in history_urls)
    fr_wiki_visited = any('fr.wikipedia.org/wiki/droits_num' in u for u in history_urls)
    eff_visited = any('eff.org/issues/international' in u for u in history_urls)

    if es_wiki_visited:
        score += 10
        feedback_parts.append("Spanish Wikipedia in history (10/10)")
    else:
        feedback_parts.append("Spanish Wikipedia NOT in history (0/10)")

    if fr_wiki_visited:
        score += 10
        feedback_parts.append("French Wikipedia in history (10/10)")
    else:
        feedback_parts.append("French Wikipedia NOT in history (0/10)")

    if eff_visited:
        score += 5
        feedback_parts.append("EFF page in history (5/5)")
    else:
        feedback_parts.append("EFF page NOT in history (0/5)")

    # 7. Check Bookmark Folder (GATE)
    folders = [f['title'] for f in result.get('folders', [])]
    folder_exists = "Digital Rights Research" in folders

    if folder_exists:
        score += 15
        feedback_parts.append("Folder 'Digital Rights Research' exists (15/15)")
    else:
        feedback_parts.append("Folder 'Digital Rights Research' missing (0/15)")

    # 8-11. Check Bookmarks inside the specific folder
    target_folder_bookmarks = [
        b for b in result.get('bookmarks', [])
        if b['folder'] == "Digital Rights Research"
    ]

    bm_es_found = False
    bm_fr_found = False
    bm_eff_found = False
    urls_correct = 0

    for bm in target_folder_bookmarks:
        bm_title = bm.get('title', '').strip()
        bm_url_norm = normalize_url(bm.get('url', ''))

        if bm_title == "Derechos Digitales - Wikipedia ES":
            bm_es_found = True
            if 'es.wikipedia.org/wiki/derechos_digitales' in bm_url_norm:
                urls_correct += 1

        elif bm_title == "Droits Numériques - Wikipedia FR":
            bm_fr_found = True
            if 'fr.wikipedia.org/wiki/droits_num' in bm_url_norm:
                urls_correct += 1

        elif bm_title == "EFF International Issues":
            bm_eff_found = True
            if 'eff.org/issues/international' in bm_url_norm:
                urls_correct += 1

    if bm_es_found:
        score += 10
        feedback_parts.append("Spanish Wiki bookmark correctly titled in folder (10/10)")
    else:
        feedback_parts.append("Spanish Wiki bookmark missing or incorrect title (0/10)")

    if bm_fr_found:
        score += 10
        feedback_parts.append("French Wiki bookmark correctly titled in folder (10/10)")
    else:
        feedback_parts.append("French Wiki bookmark missing or incorrect title (0/10)")

    if bm_eff_found:
        score += 10
        feedback_parts.append("EFF bookmark correctly titled in folder (10/10)")
    else:
        feedback_parts.append("EFF bookmark missing or incorrect title (0/10)")

    if bm_es_found and bm_fr_found and bm_eff_found and urls_correct == 3:
        score += 5
        feedback_parts.append("All 3 bookmarks map to expected URLs (5/5)")
    else:
        feedback_parts.append("One or more bookmarks map to incorrect URLs (0/5)")

    # Final logic
    passed = score >= 60 and folder_exists
    
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }