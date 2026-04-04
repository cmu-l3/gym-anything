#!/usr/bin/env python3
"""
Verifier for OSWorld Chrome task: 030eeff7-b492-4218-b312-701ec99ee0cc
Task: Can you enable the 'Do Not Track' feature in Chrome to enhance my online privacy?

Original OSWorld evaluator function: exact_match
Result type: enable_do_not_track
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
    Main verification function for task 030eeff7-b492-4218-b312-701ec99ee0cc.
    Uses OSWorld evaluator: exact_match
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        result = get_result_data(copy_from_env)
        if result is None:
            return {"passed": False, "score": 0, "feedback": "Failed to get result data"}

        # OSWorld evaluator rules
        rules = {
            "type": "enable_do_not_track",
            "expected": "true"
        }
        logger.debug(f"Result data: {result}")

        # Call the appropriate OSWorld verification function
        score = verify_with_osworld_function(result, rules)

        passed = score >= 0.5  # OSWorld uses 1.0 for pass, 0.0 for fail
        return {
            "passed": passed,
            "score": int(score * 100),
            "feedback": f"OSWorld verification result: score={score}"
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}


def get_result_data(copy_from_env):
    """Get result data based on result type."""
    result_type = "enable_do_not_track"

    # Get Do Not Track preference
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/preferences.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            prefs = json.load(f)
        os.unlink(temp_file.name)

        # Check for Do Not Track setting
        dnt_enabled = prefs.get("enable_do_not_track", False)
        return {"enable_do_not_track": str(dnt_enabled).lower()}
    except Exception as e:
        logger.error(f"Failed to get preferences: {e}")
        return None


def verify_with_osworld_function(result, rules):
    """Call the appropriate OSWorld verification function."""
    func_name = "exact_match"

    try:
        # Exact match verification for specific fields
        expected = rules.get("expected", "")
        if isinstance(result, dict):
            result_type = rules.get("type", "")
            result_value = str(result.get(result_type, "")).lower()
        else:
            result_value = str(result).lower()
        expected_value = str(expected).lower()
        logger.info(f"Comparing: result[{result_type}]='{result_value}' vs expected='{expected_value}'")
        return 1.0 if result_value == expected_value else 0.0
    except Exception as e:
        logger.error(f"Error in {func_name}: {e}", exc_info=True)
        return 0.0
