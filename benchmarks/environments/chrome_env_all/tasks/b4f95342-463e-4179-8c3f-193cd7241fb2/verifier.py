#!/usr/bin/env python3
"""
Verifier for OSWorld Chrome task: b4f95342-463e-4179-8c3f-193cd7241fb2
Task: Find the Next Available dates for Diamond.

Original OSWorld evaluator function: check_direct_json_object
Result type: active_tab_html_parse
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
    Main verification function for task b4f95342-463e-4179-8c3f-193cd7241fb2.
    Uses OSWorld evaluator: check_direct_json_object
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
            "expected": {
                "camp-sortable-column-header": {
                    "2": "camp-sortable-column-header"
                }
            }
        }

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
    result_type = "active_tab_html_parse"

    # Get active tab URL
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/final_url.txt", temp_file.name)
        with open(temp_file.name, 'r') as f:
            url = f.read().strip()
        os.unlink(temp_file.name)

        # Also try to get full tab info
        try:
            temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            copy_from_env("/tmp/active_tab_info.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                tab_info = json.load(f)
            os.unlink(temp_json.name)
            return {"url": url, **tab_info}
        except:
            return {"url": url}
    except Exception as e:
        logger.error(f"Failed to get URL: {e}")
        return None


def verify_with_osworld_function(result, rules):
    """Call the appropriate OSWorld verification function."""
    func_name = "check_direct_json_object"

    try:
        # Direct JSON object comparison
        expected = rules.get("expected", {})
        if not isinstance(result, dict):
            return 0.0

        # Check all expected fields match
        for key, expected_value in expected.items():
            if key not in result:
                logger.info(f"Missing key: {key}")
                return 0.0
            if str(result[key]).lower() != str(expected_value).lower():
                logger.info(f"Mismatch for {key}: expected {expected_value}, got {result[key]}")
                return 0.0
        return 1.0
    except Exception as e:
        logger.error(f"Error in {func_name}: {e}", exc_info=True)
        return 0.0
