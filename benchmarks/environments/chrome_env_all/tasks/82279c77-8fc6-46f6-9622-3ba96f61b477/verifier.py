#!/usr/bin/env python3
"""
Verifier for OSWorld Chrome task: 82279c77-8fc6-46f6-9622-3ba96f61b477
Task: Find electric cars with a maximum price of $50,000 within 50 miles of 10001.

Original OSWorld evaluator function: check_direct_json_object
Result type: active_tab_url_parse
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
    Main verification function for task 82279c77-8fc6-46f6-9622-3ba96f61b477.
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
                "list_price_max": "50000",
                "maximum_distance": "50",
                "zip": "10001",
                "fuel_slugs[]": "electric"
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
    result_type = "active_tab_url_parse"

    # Get active tab URL and parse query parameters
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/final_url.txt", temp_file.name)
        with open(temp_file.name, 'r') as f:
            url = f.read().strip()
        os.unlink(temp_file.name)

        logger.info(f"Parsing URL: {url}")

        # Parse URL and extract query parameters
        parsed_url = urlparse(url)
        query_params = parse_qs(parsed_url.query)

        # Convert query params to the format expected by verifier
        # parse_qs returns lists, so we need to extract values
        result = {}
        for key, value_list in query_params.items():
            # For keys like "fuel_slugs[]", keep the brackets
            # Take first value from list (or join if multiple)
            if len(value_list) == 1:
                result[key] = value_list[0]
            else:
                result[key] = ','.join(value_list)

        logger.info(f"Parsed query parameters: {result}")
        return result

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
