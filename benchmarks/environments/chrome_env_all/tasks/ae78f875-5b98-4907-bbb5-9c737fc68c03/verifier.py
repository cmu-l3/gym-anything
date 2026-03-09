#!/usr/bin/env python3
"""
Verifier for OSWorld Chrome task: ae78f875-5b98-4907-bbb5-9c737fc68c03
Task: Could you please change the number of search results displayed on one page to 50? I find that having more results visible at once significantly enhances my research efficiency, as it reduces the need to constantly click through multiple pages. 

Original OSWorld evaluator function: infeasible
Result type: active_url_from_accessTree
"""

import logging
import sys
import os
import json
import re
import sqlite3
import tempfile
from pathlib import Path
from urllib.parse import urlparse, parse_qs, urlunparse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import OSWorld verification functions
sys.path.insert(0, '/data/Gym-Anything')
from osworld_all_verifs_chrome import (
    is_expected_active_tab,
    is_expected_active_tab_approximate,
    is_expected_url_pattern_match,
    is_expected_tabs,
    is_expected_bookmarks,
    is_expected_search_query,
    is_expected_installed_extensions,
    is_cookie_deleted,
    is_shortcut_on_desktop,
    check_history_deleted,
    check_enabled_experiments,
    check_font_size,
    is_added_to_steam_cart,
    compare_pdfs,
    compare_pdf_images,
    compare_archive,
    compare_htmls
)


def verify_task(traj, env_info, task_info):
    """
    Main verification function for task ae78f875-5b98-4907-bbb5-9c737fc68c03.
    Uses OSWorld evaluator: infeasible
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        result = get_result_data(copy_from_env)
        if result is None:
            return {"passed": False, "score": 0, "feedback": "Failed to get result data"}

        score = verify_with_osworld_function(traj, result)
        passed = score >= 0.7
        return {
            "passed": passed,
            "score": int(score * 100),
            "feedback": f"Heuristic verification result: score={score:.2f}",
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}


def get_result_data(copy_from_env):
    """Capture the active Chrome tab URL and tab metadata."""
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/final_url.txt", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8', errors='ignore') as f:
            url = f.read().strip()
        os.unlink(temp_file.name)
    except Exception as e:
        logger.error(f"Failed to get URL: {e}")
        return None

    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/active_tab_info.json", temp_json.name)
        with open(temp_json.name, 'r', encoding='utf-8', errors='ignore') as f:
            tab_info = json.load(f)
        os.unlink(temp_json.name)
    except Exception:
        tab_info = {}

    return {"url": url, **tab_info}


def verify_with_osworld_function(traj, result):
    """Heuristic verifier for an OSWorld task whose source evaluator was infeasible."""
    score = 0.0
    url = (result.get("url") or "").lower()
    if "num=50" in url:
        score += 0.7
    elif "preferences" in url or "search" in url:
        score += 0.2

    final_screenshot = traj.get("final_screenshot")
    if final_screenshot and Path(final_screenshot).exists():
        prompt = """
        You are verifying a Chrome search settings task.
        Determine whether the browser is configured to show 50 search results per page.
        Return JSON with:
        {
          "search_settings_visible": bool,
          "results_per_page_visible": bool,
          "fifty_selected_or_indicated": bool
        }
        """
        vlm_result = query_vlm(prompt=prompt, image=final_screenshot)
        parsed = vlm_result.get("parsed", {}) if isinstance(vlm_result, dict) else {}
        if parsed.get("search_settings_visible"):
            score += 0.1
        if parsed.get("results_per_page_visible"):
            score += 0.1
        if parsed.get("fifty_selected_or_indicated"):
            score += 0.1

    return min(score, 1.0)
