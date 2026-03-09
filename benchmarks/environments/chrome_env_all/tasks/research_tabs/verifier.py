#!/usr/bin/env python3
"""
Verifier for Chrome Multi-Tab Research Task: research_tabs@1
Task: Open multiple research tabs (Python docs, MDN, Stack Overflow) to organize web resources

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) to query all open tabs
- Verifies exactly 4 tabs are open (original + 3 research tabs)
- Checks that all expected URLs are present
- Validates tab titles contain expected keywords
- Ensures no error pages or duplicate URLs
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from urllib.parse import urlparse
from typing import Dict, List, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for research_tabs@1 task.
    
    Args:
        traj: Trajectory data (unused for this task)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Get tab data from container
        tabs_data = get_tabs_data(copy_from_env)
        if tabs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve tab information from Chrome CDP"
            }

        # Perform multi-criteria verification
        verification_result = verify_research_tabs(tabs_data)
        
        # Clean up temporary files
        cleanup_verification_temp()
        
        return verification_result

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_tabs_data(copy_from_env) -> List[Dict[str, Any]]:
    """
    Retrieve tab information from container using CDP data.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        List of tab dictionaries with 'url', 'title', and other metadata
    """
    try:
        # Copy the CDP JSON data from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/chrome_page_tabs.json", temp_path)
        
        with open(temp_path, 'r') as f:
            tabs_data = json.load(f)
        
        os.unlink(temp_path)
        
        logger.info(f"Successfully retrieved {len(tabs_data)} tab(s) from CDP")
        return tabs_data
        
    except Exception as e:
        logger.error(f"Failed to get tabs data: {e}")
        return None


def verify_research_tabs(tabs_data: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify that research tabs were correctly opened.
    
    Checks:
    1. Exactly 4 tabs are open
    2. All expected URLs are present (Python docs, MDN, Stack Overflow)
    3. Tab titles contain expected keywords
    4. No error pages detected
    5. No duplicate research URLs
    
    Args:
        tabs_data: List of tab information from CDP
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    # Expected research URLs (with flexibility for exact paths)
    expected_urls = {
        "python": "https://docs.python.org/3/",
        "mdn": "https://developer.mozilla.org/en-US/",
        "stackoverflow": "https://stackoverflow.com/"
    }
    
    # Extract URLs and titles from tabs
    tab_urls = [tab.get('url', '') for tab in tabs_data]
    tab_titles = [tab.get('title', '') for tab in tabs_data]
    
    logger.info(f"Found {len(tabs_data)} tabs")
    for i, (url, title) in enumerate(zip(tab_urls, tab_titles), 1):
        logger.info(f"  Tab {i}: {url[:60]}... | {title[:50]}...")
    
    # Criterion 1: Tab count (exactly 4 tabs)
    tab_count_ok = len(tabs_data) == 4
    logger.info(f"✓ Tab count check: {len(tabs_data)} tabs (expected 4) - {'PASS' if tab_count_ok else 'FAIL'}")
    
    # Criterion 2: Check all expected URLs are present
    urls_found = {
        "python": False,
        "mdn": False,
        "stackoverflow": False
    }
    
    for url in tab_urls:
        url_lower = url.lower()
        if "docs.python.org/3" in url_lower:
            urls_found["python"] = True
        if "developer.mozilla.org" in url_lower:
            urls_found["mdn"] = True
        if "stackoverflow.com" in url_lower:
            urls_found["stackoverflow"] = True
    
    all_urls_present = all(urls_found.values())
    logger.info(f"✓ URL presence check: Python={urls_found['python']}, MDN={urls_found['mdn']}, StackOverflow={urls_found['stackoverflow']} - {'PASS' if all_urls_present else 'FAIL'}")
    
    # Criterion 3: Verify titles contain expected keywords
    title_checks = {
        "python": False,
        "mdn": False,
        "stackoverflow": False
    }
    
    for title in tab_titles:
        title_lower = title.lower()
        if "python" in title_lower and ("documentation" in title_lower or "docs" in title_lower):
            title_checks["python"] = True
        if any(kw in title_lower for kw in ["mdn", "mozilla", "web docs"]):
            title_checks["mdn"] = True
        if "stack overflow" in title_lower:
            title_checks["stackoverflow"] = True
    
    titles_valid = all(title_checks.values())
    logger.info(f"✓ Title validation: Python={title_checks['python']}, MDN={title_checks['mdn']}, StackOverflow={title_checks['stackoverflow']} - {'PASS' if titles_valid else 'FAIL'}")
    
    # Criterion 4: Check for error pages
    error_keywords = ["error", "404", "not found", "page not found", "cannot be reached"]
    has_errors = any(
        any(keyword in title.lower() for keyword in error_keywords)
        for title in tab_titles
    )
    no_errors = not has_errors
    logger.info(f"✓ Error page check: {'No errors detected' if no_errors else 'ERROR PAGES FOUND'} - {'PASS' if no_errors else 'FAIL'}")
    
    # Criterion 5: Check for duplicate research URLs
    research_urls_found = []
    for url in tab_urls:
        url_lower = url.lower()
        if "docs.python.org" in url_lower:
            research_urls_found.append("python")
        elif "developer.mozilla.org" in url_lower:
            research_urls_found.append("mdn")
        elif "stackoverflow.com" in url_lower:
            research_urls_found.append("stackoverflow")
    
    unique_research_count = len(set(research_urls_found))
    no_duplicates = unique_research_count == len(research_urls_found) and unique_research_count == 3
    logger.info(f"✓ Duplicate check: Found {len(research_urls_found)} research URLs, {unique_research_count} unique - {'PASS' if no_duplicates else 'FAIL'}")
    
    # Calculate score based on criteria met
    criteria_results = [
        tab_count_ok,
        all_urls_present,
        titles_valid,
        no_errors,
        no_duplicates
    ]
    
    criteria_met = sum(criteria_results)
    score = (criteria_met / 5) * 100
    passed = score >= 75  # Need at least 4/5 criteria (75%)
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Verification Results: {criteria_met}/5 criteria met")
    feedback_parts.append(f"- Tab count: {'✓' if tab_count_ok else '✗'} ({len(tabs_data)} tabs, expected 4)")
    feedback_parts.append(f"- URLs present: {'✓' if all_urls_present else '✗'} (Python: {urls_found['python']}, MDN: {urls_found['mdn']}, StackOverflow: {urls_found['stackoverflow']})")
    feedback_parts.append(f"- Titles valid: {'✓' if titles_valid else '✗'}")
    feedback_parts.append(f"- No errors: {'✓' if no_errors else '✗'}")
    feedback_parts.append(f"- No duplicates: {'✓' if no_duplicates else '✗'}")
    
    if passed:
        feedback_parts.append("✅ Task completed successfully!")
    else:
        feedback_parts.append("❌ Task incomplete - missing required tabs or criteria")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": {
            "tab_count": len(tabs_data),
            "criteria_met": criteria_met,
            "urls_found": urls_found,
            "title_checks": title_checks,
            "has_errors": has_errors,
            "has_duplicates": not no_duplicates,
            "tab_urls": tab_urls,
            "tab_titles": tab_titles
        }
    }
