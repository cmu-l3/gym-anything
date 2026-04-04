#!/usr/bin/env python3
"""
Verifier for Chrome Tab Search and Navigation Task (tab_search_navigation@1)
Task: Use Chrome's tab search feature to locate and navigate to a specific target tab

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) to query all open tabs
- Identifies the currently active/focused tab
- Compares active tab URL and title against expected target
- Ensures the correct tab was successfully navigated to
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for tab_search_navigation@1 task.
    
    Verifies that the agent successfully used tab search to navigate
    to the target Wikipedia Browser Extension tab.
    
    Args:
        traj: Trajectory data (unused)
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
        # Get target tab information
        target_url, target_keywords = get_target_info(copy_from_env)
        if not target_url:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not retrieve target tab information"
            }
        
        logger.info(f"Target URL: {target_url}")
        logger.info(f"Target keywords: {target_keywords}")
        
        # Get all tabs and active tab information
        all_tabs, active_tab = get_tabs_info(copy_from_env)
        if active_tab is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not retrieve active tab information from Chrome"
            }
        
        # Perform verification
        verification_result = verify_tab_navigation(
            active_tab=active_tab,
            all_tabs=all_tabs,
            target_url=target_url,
            target_keywords=target_keywords
        )
        
        # Clean up
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


def get_target_info(copy_from_env) -> Tuple[str, List[str]]:
    """
    Retrieve target tab URL and keywords from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (target_url, target_keywords_list)
    """
    try:
        # Copy target URL file
        temp_url = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_url.close()
        
        copy_from_env("/tmp/tab_search_task/target_url.txt", temp_url.name)
        
        with open(temp_url.name, 'r') as f:
            target_url = f.read().strip()
        
        os.unlink(temp_url.name)
        
        # Copy target keywords file
        temp_keywords = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_keywords.close()
        
        copy_from_env("/tmp/tab_search_task/target_keywords.txt", temp_keywords.name)
        
        with open(temp_keywords.name, 'r') as f:
            keywords_str = f.read().strip()
            target_keywords = [kw.strip() for kw in keywords_str.split(',') if kw.strip()]
            if not target_keywords:
                target_keywords = keywords_str.split()
        
        os.unlink(temp_keywords.name)
        
        return target_url, target_keywords
        
    except Exception as e:
        logger.error(f"Failed to get target info: {e}")
        return "", []


def get_tabs_info(copy_from_env) -> Tuple[List[Dict[str, Any]], Optional[Dict[str, Any]]]:
    """
    Retrieve all tabs and identify active tab from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (all_tabs_list, active_tab_dict)
    """
    try:
        # Copy active tab info
        temp_active = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_active.close()
        
        copy_from_env("/tmp/tab_search_task/active_tab.json", temp_active.name)
        
        with open(temp_active.name, 'r') as f:
            active_tab = json.load(f)
        
        os.unlink(temp_active.name)
        
        # Copy all tabs info
        temp_all = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_all.close()
        
        copy_from_env("/tmp/tab_search_task/page_tabs.json", temp_all.name)
        
        with open(temp_all.name, 'r') as f:
            all_tabs = json.load(f)
        
        os.unlink(temp_all.name)
        
        logger.info(f"Retrieved {len(all_tabs)} tabs, active tab: {active_tab.get('title', 'unknown')[:50]}")
        
        return all_tabs, active_tab
        
    except Exception as e:
        logger.error(f"Failed to get tabs info: {e}")
        return [], None


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison by removing protocol, trailing slashes, etc.
    
    Args:
        url: URL string to normalize
        
    Returns:
        Normalized URL string
    """
    if not url:
        return ""
    
    url = url.lower().strip()
    # Remove protocol
    url = re.sub(r'^https?://', '', url)
    # Remove www.
    url = re.sub(r'^www\.', '', url)
    # Remove trailing slashes
    url = url.rstrip('/')
    # Remove query parameters for main URL matching
    url = url.split('?')[0]
    # Remove URL fragments
    url = url.split('#')[0]
    
    return url


def verify_tab_navigation(
    active_tab: Dict[str, Any],
    all_tabs: List[Dict[str, Any]],
    target_url: str,
    target_keywords: List[str]
) -> Dict[str, Any]:
    """
    Verify that the agent successfully navigated to the target tab.
    
    Checks:
    1. Multiple tabs are open (5+ tabs expected)
    2. Active tab URL matches target URL
    3. Active tab title contains target keywords
    4. Tab is not an error page
    5. Navigation occurred (tab was actually switched)
    
    Args:
        active_tab: Currently active tab information from CDP
        all_tabs: List of all open tabs
        target_url: Expected target URL
        target_keywords: Expected keywords in title
        
    Returns:
        Verification result with passed, score, and feedback
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    active_url = active_tab.get('url', '')
    active_title = active_tab.get('title', '')
    
    logger.info(f"Active tab URL: {active_url}")
    logger.info(f"Active tab title: {active_title}")
    
    # Criterion 1: Multiple tabs open
    tab_count = len(all_tabs)
    multiple_tabs_ok = tab_count >= 5
    
    if multiple_tabs_ok:
        criteria_met += 1
        feedback_parts.append(f"✓ Multiple tabs present: {tab_count} tabs")
        logger.info(f"✓ Tab count check: {tab_count} tabs (expected ≥5) - PASS")
    else:
        feedback_parts.append(f"✗ Insufficient tabs: {tab_count} tabs (expected ≥5)")
        logger.info(f"✗ Tab count check: {tab_count} tabs (expected ≥5) - FAIL")
    
    # Criterion 2: URL matches target
    normalized_active = normalize_url(active_url)
    normalized_target = normalize_url(target_url)
    
    # Check for exact match or contains match
    url_match = (
        normalized_active == normalized_target or
        normalized_target in normalized_active or
        normalized_active in normalized_target
    )
    
    if url_match:
        criteria_met += 1
        feedback_parts.append(f"✓ Correct URL: {active_url}")
        logger.info(f"✓ URL match check: PASS")
    else:
        feedback_parts.append(f"✗ URL mismatch: got '{active_url}', expected '{target_url}'")
        logger.info(f"✗ URL match check: FAIL")
    
    # Criterion 3: Title contains keywords
    title_lower = active_title.lower()
    keywords_found = []
    
    for keyword in target_keywords:
        if keyword.lower() in title_lower:
            keywords_found.append(keyword)
    
    # Need at least one keyword match
    title_match = len(keywords_found) > 0
    
    if title_match:
        criteria_met += 1
        feedback_parts.append(f"✓ Title keywords found: {', '.join(keywords_found)}")
        logger.info(f"✓ Title match check: Found {len(keywords_found)} keywords - PASS")
    else:
        feedback_parts.append(f"✗ Title keywords missing in '{active_title}'")
        logger.info(f"✗ Title match check: No keywords found - FAIL")
    
    # Criterion 4: Not an error page
    error_indicators = [
        '404', 'not found', 'error', 'cannot be reached',
        'unable to connect', 'page not available', 'problem loading'
    ]
    
    is_error_page = any(
        indicator in title_lower or indicator in active_url.lower()
        for indicator in error_indicators
    )
    
    not_error = not is_error_page
    
    if not_error:
        criteria_met += 1
        feedback_parts.append("✓ Valid page loaded (not an error page)")
        logger.info("✓ Error page check: Not an error page - PASS")
    else:
        feedback_parts.append("✗ Error page detected")
        logger.info("✗ Error page check: Error page detected - FAIL")
    
    # Criterion 5: Navigation occurred (active tab is the target)
    # Check that we're not just on the first tab by chance
    target_tab_exists = False
    for tab in all_tabs:
        tab_url = tab.get('url', '')
        if normalize_url(tab_url) == normalized_target:
            target_tab_exists = True
            break
    
    navigation_occurred = url_match and target_tab_exists
    
    if navigation_occurred:
        criteria_met += 1
        feedback_parts.append("✓ Successfully navigated to target tab")
        logger.info("✓ Navigation check: Target tab is active - PASS")
    else:
        if not target_tab_exists:
            feedback_parts.append("✗ Target tab not found among open tabs")
            logger.info("✗ Navigation check: Target tab not in tab list - FAIL")
        else:
            feedback_parts.append("✗ Target tab exists but is not active")
            logger.info("✗ Navigation check: Target tab exists but not active - FAIL")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 4/5 criteria (75%)
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if passed:
        feedback += f"\n\n✅ Successfully used tab search to navigate to target tab!"
        feedback += f"\nActive tab: {active_title}"
    else:
        feedback += f"\n\n❌ Task incomplete - did not successfully navigate to target tab"
        if not url_match:
            feedback += f"\n   Expected to navigate to: {target_url}"
            feedback += f"\n   Currently on: {active_url}"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "active_url": active_url,
            "active_title": active_title,
            "target_url": target_url,
            "tab_count": tab_count,
            "criteria_met": criteria_met,
            "url_match": url_match,
            "title_match": title_match,
            "not_error": not_error,
            "navigation_occurred": navigation_occurred
        }
    }
