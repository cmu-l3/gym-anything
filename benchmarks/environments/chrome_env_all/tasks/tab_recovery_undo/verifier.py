#!/usr/bin/env python3
"""
Verifier for Chrome Tab Recovery Task: tab_recovery_undo@1
Task: Close the GitHub tab and recover it using Ctrl+Shift+T

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) to query final tab state
- Verifies exactly 3 tabs are open (recovery successful)
- Checks that GitHub URL is present among tabs
- Validates tab is active and fully loaded
- Ensures no duplicate or missing tabs
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback")
    def cleanup_verification_temp():
        pass


# Target URLs for verification
EXPECTED_TAB_COUNT = 3
TARGET_GITHUB_URL = "github.com/torvalds/linux"
WIKIPEDIA_URL = "wikipedia.org/wiki/Computer"
STACKOVERFLOW_URL = "stackoverflow.com/questions/11227809"


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for tab_recovery_undo@1 task.
    
    Verifies:
    1. Correct number of tabs (3) - back to original state
    2. GitHub URL is present (recovery successful)
    3. All original URLs present (Wikipedia, GitHub, Stack Overflow)
    4. No duplicate tabs
    5. Tabs are valid (not error pages)
    
    Args:
        traj: Trajectory data
        env_info: Environment information including copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details'
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
        verification_result = verify_tab_recovery(tabs_data)
        
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
        List of tab dictionaries with 'url', 'title', and metadata
    """
    try:
        # Copy the CDP JSON data from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try to copy the final tab state
        copy_from_env("/tmp/chrome_page_tabs_final.json", temp_path)
        
        with open(temp_path, 'r') as f:
            tabs_data = json.load(f)
        
        os.unlink(temp_path)
        
        logger.info(f"Successfully retrieved {len(tabs_data)} tab(s) from CDP")
        return tabs_data
        
    except Exception as e:
        logger.error(f"Failed to get tabs data: {e}")
        return None


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison.
    
    Args:
        url: URL string
        
    Returns:
        Normalized URL (lowercase, no protocol, no trailing slash)
    """
    if not url:
        return ""
    
    url = url.lower()
    # Remove protocol
    url = re.sub(r'^https?://', '', url)
    # Remove www
    url = re.sub(r'^www\.', '', url)
    # Remove trailing slash
    url = url.rstrip('/')
    # Remove query parameters for comparison
    url = url.split('?')[0]
    
    return url


def check_url_present(tabs: List[Dict], target_url_fragment: str) -> Tuple[bool, str]:
    """
    Check if a URL containing the target fragment is present in tabs.
    
    Args:
        tabs: List of tab dictionaries
        target_url_fragment: URL fragment to search for (e.g., "github.com/torvalds/linux")
        
    Returns:
        Tuple of (is_present: bool, matching_url: str)
    """
    target_normalized = normalize_url(target_url_fragment)
    
    for tab in tabs:
        url = tab.get('url', '')
        url_normalized = normalize_url(url)
        
        if target_normalized in url_normalized:
            return True, url
    
    return False, ""


def verify_tab_recovery(tabs_data: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify that tab recovery was successful.
    
    Checks 5 criteria:
    1. Tab count is exactly 3
    2. GitHub URL is present
    3. All 3 expected URLs present (Wikipedia, GitHub, Stack Overflow)
    4. No duplicate URLs
    5. All tabs are valid (not error pages)
    
    Args:
        tabs_data: List of tab information from CDP
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    # Extract URLs and titles from tabs
    tab_urls = [tab.get('url', '') for tab in tabs_data]
    tab_titles = [tab.get('title', '') for tab in tabs_data]
    
    logger.info(f"Verifying {len(tabs_data)} tabs")
    for i, (url, title) in enumerate(zip(tab_urls, tab_titles), 1):
        logger.info(f"  Tab {i}: {url[:70]}... | {title[:40]}...")
    
    # Criterion 1: Tab count (exactly 3 tabs)
    tab_count_correct = len(tabs_data) == EXPECTED_TAB_COUNT
    logger.info(f"Criterion 1 - Tab count: {len(tabs_data)} (expected {EXPECTED_TAB_COUNT}) - {'PASS' if tab_count_correct else 'FAIL'}")
    
    # Criterion 2: GitHub URL present (recovery successful)
    github_present, github_url = check_url_present(tabs_data, TARGET_GITHUB_URL)
    logger.info(f"Criterion 2 - GitHub URL present: {github_present} - {'PASS' if github_present else 'FAIL'}")
    
    # Criterion 3: All expected URLs present
    wikipedia_present, _ = check_url_present(tabs_data, WIKIPEDIA_URL)
    stackoverflow_present, _ = check_url_present(tabs_data, STACKOVERFLOW_URL)
    
    all_urls_present = github_present and wikipedia_present and stackoverflow_present
    logger.info(f"Criterion 3 - All URLs present: GitHub={github_present}, Wikipedia={wikipedia_present}, StackOverflow={stackoverflow_present} - {'PASS' if all_urls_present else 'FAIL'}")
    
    # Criterion 4: No duplicate URLs
    normalized_urls = [normalize_url(url) for url in tab_urls]
    unique_count = len(set(normalized_urls))
    no_duplicates = unique_count == len(tab_urls)
    logger.info(f"Criterion 4 - No duplicates: {len(tab_urls)} tabs, {unique_count} unique - {'PASS' if no_duplicates else 'FAIL'}")
    
    # Criterion 5: All tabs are valid (not error pages)
    error_keywords = ["error", "404", "not found", "cannot be reached", "connection failed"]
    has_errors = False
    
    for title in tab_titles:
        title_lower = title.lower()
        if any(keyword in title_lower for keyword in error_keywords):
            has_errors = True
            logger.warning(f"Error detected in tab title: {title}")
            break
    
    # Also check for chrome-error:// URLs
    for url in tab_urls:
        if 'chrome-error://' in url.lower() or 'about:blank' in url.lower():
            has_errors = True
            logger.warning(f"Error URL detected: {url}")
            break
    
    no_errors = not has_errors
    logger.info(f"Criterion 5 - No errors: {'PASS' if no_errors else 'FAIL (error pages detected)'}")
    
    # Calculate score based on criteria met
    criteria_results = [
        tab_count_correct,
        github_present,
        all_urls_present,
        no_duplicates,
        no_errors
    ]
    
    criteria_met = sum(criteria_results)
    score = int((criteria_met / 5) * 100)
    passed = score >= 80  # Need at least 4/5 criteria (80%)
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Tab Recovery Verification: {criteria_met}/5 criteria met")
    feedback_parts.append("")
    feedback_parts.append(f"1. Tab count: {'✓' if tab_count_correct else '✗'} ({len(tabs_data)} tabs, expected {EXPECTED_TAB_COUNT})")
    feedback_parts.append(f"2. GitHub URL recovered: {'✓' if github_present else '✗ MISSING'}")
    feedback_parts.append(f"3. All URLs present:")
    feedback_parts.append(f"   - Wikipedia: {'✓' if wikipedia_present else '✗'}")
    feedback_parts.append(f"   - GitHub: {'✓' if github_present else '✗'}")
    feedback_parts.append(f"   - Stack Overflow: {'✓' if stackoverflow_present else '✗'}")
    feedback_parts.append(f"4. No duplicates: {'✓' if no_duplicates else '✗ (duplicates detected)'}")
    feedback_parts.append(f"5. No error pages: {'✓' if no_errors else '✗ (errors detected)'}")
    feedback_parts.append("")
    
    if passed:
        if criteria_met == 5:
            feedback_parts.append("✅ Perfect! Tab recovery successful - all criteria met.")
        else:
            feedback_parts.append("✅ Task completed successfully with minor issues.")
    else:
        feedback_parts.append("❌ Task incomplete - tab recovery failed or tabs are incorrect.")
        if not github_present:
            feedback_parts.append("   → GitHub tab was not recovered using Ctrl+Shift+T")
        if not tab_count_correct:
            if len(tabs_data) < EXPECTED_TAB_COUNT:
                feedback_parts.append(f"   → Too few tabs ({len(tabs_data)}/{EXPECTED_TAB_COUNT})")
            else:
                feedback_parts.append(f"   → Too many tabs ({len(tabs_data)}/{EXPECTED_TAB_COUNT})")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "tab_count": len(tabs_data),
            "expected_tab_count": EXPECTED_TAB_COUNT,
            "criteria_met": criteria_met,
            "checks": {
                "tab_count_correct": tab_count_correct,
                "github_present": github_present,
                "wikipedia_present": wikipedia_present,
                "stackoverflow_present": stackoverflow_present,
                "all_urls_present": all_urls_present,
                "no_duplicates": no_duplicates,
                "no_errors": no_errors
            },
            "tab_urls": tab_urls,
            "tab_titles": tab_titles
        }
    }
