#!/usr/bin/env python3
"""
Verifier for OSWorld Chrome task: e1e75309-3ddb-4d09-92ec-de869c928143
Task: Computer, can you turn the webpage I'm looking at into a PDF file, save it to my Desktop with the default filename and set the margins to none?

Original OSWorld evaluator function: compare_pdfs
Result type: vm_file
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
    Main verification function for task e1e75309-3ddb-4d09-92ec-de869c928143.
    Uses OSWorld evaluator: compare_pdfs
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        result = get_result_data(copy_from_env)
        if result is None:
            return {"passed": False, "score": 0, "feedback": "Failed to get result data"}

        score = verify_with_osworld_function(result)
        passed = score >= 0.8
        return {
            "passed": passed,
            "score": int(score * 100),
            "feedback": f"PDF export verification result: score={score:.2f}",
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}


def get_result_data(copy_from_env):
    """Load the exported PDF metadata and copied PDF artifact."""
    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/pdf_export_result.json", temp_json.name)
        with open(temp_json.name, 'r', encoding='utf-8', errors='ignore') as f:
            data = json.load(f)
        os.unlink(temp_json.name)
        return data
    except Exception as e:
        logger.error(f"Failed to get PDF export result: {e}")
        return None


def verify_with_osworld_function(result):
    """Verify that a new PDF was produced and copied by the export hook."""
    score = 0.0
    if result.get("pdf_exists"):
        score += 0.4
    if result.get("pdf_created_during_task"):
        score += 0.3
    if result.get("pdf_size_bytes", 0) >= 20_000:
        score += 0.2
    if result.get("pdf_path"):
        score += 0.1
    return min(score, 1.0)
