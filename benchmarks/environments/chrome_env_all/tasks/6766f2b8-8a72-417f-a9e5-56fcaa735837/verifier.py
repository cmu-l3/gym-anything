#!/usr/bin/env python3
"""
Verifier for OSWorld Chrome task: 6766f2b8-8a72-417f-a9e5-56fcaa735837
Task: Could you help me unzip the downloaded extension file from /home/user/Desktop/ to /home/user/Desktop/ and configure it in Chrome's extensions?

Original OSWorld evaluator function: is_in_list
Result type: find_unpacked_extension_path
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
    Main verification function for task 6766f2b8-8a72-417f-a9e5-56fcaa735837.
    Uses OSWorld evaluator: is_in_list
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
            "expected": "/home/user/Desktop/helloExtension"
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
    result_type = "find_unpacked_extension_path"

    # Default: get URL
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/final_url.txt", temp_file.name)
        with open(temp_file.name, 'r') as f:
            url = f.read().strip()
        os.unlink(temp_file.name)
        return url
    except Exception as e:
        logger.error(f"Failed to get result: {e}")
        return None


def verify_with_osworld_function(result, rules):
    """Call the appropriate OSWorld verification function."""
    func_name = "is_in_list"

    try:
        # Default: URL pattern matching
        return is_expected_url_pattern_match(result, rules)
    except Exception as e:
        logger.error(f"Error in {func_name}: {e}", exc_info=True)
        return 0.0
