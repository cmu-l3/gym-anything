#!/usr/bin/env python3
"""
Verifier for Chrome Recently Closed Tabs Recovery Task: recently_closed_recovery@1
Task: Open 4 tabs, close 3, then selectively recover 2 using Recently Closed feature

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) to query currently open tabs
- Uses Chrome History database to verify all 4 URLs were visited
- Checks that exactly 3 tabs are open (Wikipedia, GitHub, Hacker News)
- Verifies Stack Overflow is NOT among the open tabs
- Ensures no duplicate tabs were created
"""

import logging
import sys
import os
import json
import sqlite3
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


# Expected URLs for the task
EXPECTED_URLS = {
    "wikipedia": "https://en.wikipedia.org/wiki/Artificial_intelligence",
    "github": "https://github.com/trending",
    "hackernews": "https://news.ycombinator.com",
    "stackoverflow": "https://stackoverflow.com/questions"
}

EXPECTED_OPEN = ["wikipedia", "github", "hackernews"]
EXPECTED_CLOSED = ["stackoverflow"]


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for recently_closed_recovery@1 task.
    
    Verification Criteria (5 total, need 4+ to pass @ 80%):
    1. All 4 URLs were visited (History check)
    2. Exactly 3 tabs are currently open (CDP check)
    3. Correct tabs are open (Wikipedia, GitHub, Hacker News)
    4. Stack Overflow is NOT open
    5. No duplicate tabs
    
    Args:
        traj: Trajectory data (not used)
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
        # Step 1: Get current tab state from CDP
        logger.info("Step 1: Retrieving current tab state from CDP...")
        tabs_data, cdp_error = get_tabs_from_cdp(copy_from_env)
        
        if tabs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve tab information: {cdp_error}"
            }
        
        # Step 2: Get browsing history to verify all URLs were visited
        logger.info("Step 2: Retrieving browsing history...")
        history_data, history_error = get_history_from_db(copy_from_env)
        
        if history_data is None:
            logger.warning(f"History check failed: {history_error}")
            # Continue with partial verification
            history_data = []
        
        # Step 3: Perform comprehensive verification
        logger.info("Step 3: Performing multi-criteria verification...")
        result = verify_tab_recovery(tabs_data, history_data)
        
        # Clean up temporary files
        cleanup_verification_temp()
        
        return result

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_tabs_from_cdp(copy_from_env) -> Tuple[Optional[List[Dict]], str]:
    """
    Retrieve current tab information from CDP data.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (tabs_data: List[Dict] or None, error_message: str)
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try to copy CDP data
        possible_paths = [
            "/tmp/chrome_page_tabs_recovery.json",
            "/tmp/chrome_all_tabs_recovery.json"
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy CDP data from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                with open(temp_path, 'r') as f:
                    tabs_data = json.load(f)
                
                # Filter to page tabs if needed
                if isinstance(tabs_data, list):
                    page_tabs = [tab for tab in tabs_data if tab.get('type') == 'page']
                    logger.info(f"✓ Retrieved {len(page_tabs)} page tab(s) from CDP")
                    os.unlink(temp_path)
                    return page_tabs, ""
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        return None, "Could not retrieve CDP data from any location"
        
    except Exception as e:
        if temp_file and os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
        return None, f"Error retrieving CDP data: {e}"


def get_history_from_db(copy_from_env) -> Tuple[Optional[List[Tuple[str, str]]], str]:
    """
    Retrieve browsing history from Chrome History database.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (history_data: List[(url, title)] or None, error_message: str)
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.db', mode='w+b')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try to copy History database
        possible_paths = [
            "/tmp/chrome_history_recovery.db",
            "/home/ga/.config/google-chrome-cdp/Default/History",
            "/home/ga/.config/google-chrome/Default/History"
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy History from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if it's a valid SQLite database
                if os.path.getsize(temp_path) < 100:
                    logger.debug(f"File too small, trying next location")
                    continue
                
                # Query the database
                conn = sqlite3.connect(temp_path)
                cursor = conn.cursor()
                
                # Get recent URLs (last 100 entries)
                cursor.execute(
                    "SELECT url, title FROM urls ORDER BY last_visit_time DESC LIMIT 100"
                )
                history_data = cursor.fetchall()
                conn.close()
                
                logger.info(f"✓ Retrieved {len(history_data)} history entries")
                os.unlink(temp_path)
                return history_data, ""
                
            except sqlite3.DatabaseError as e:
                logger.debug(f"Database error for {container_path}: {e}")
                continue
            except Exception as e:
                logger.debug(f"Failed to copy/parse from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        return None, "Could not retrieve valid History database from any location"
        
    except Exception as e:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
        return None, f"Error retrieving History: {e}"


def normalize_url(url: str) -> str:
    """Normalize URL for comparison."""
    if not url:
        return ""
    # Remove protocol
    url = url.replace('https://', '').replace('http://', '')
    # Remove trailing slashes
    url = url.rstrip('/')
    # Convert to lowercase
    url = url.lower()
    # Remove query parameters for comparison
    if '?' in url:
        url = url.split('?')[0]
    return url


def check_url_match(url: str, expected_url: str) -> bool:
    """Check if a URL matches the expected URL (flexible matching)."""
    norm_url = normalize_url(url)
    norm_expected = normalize_url(expected_url)
    
    # Direct match
    if norm_url == norm_expected:
        return True
    
    # Substring match (for URLs with additional paths)
    if norm_expected in norm_url:
        return True
    
    # Handle specific cases
    if "wikipedia.org/wiki/artificial" in norm_url and "wikipedia.org/wiki/artificial" in norm_expected:
        return True
    if "github.com/trending" in norm_url and "github.com/trending" in norm_expected:
        return True
    if "news.ycombinator.com" in norm_url and "news.ycombinator.com" in norm_expected:
        return True
    if "stackoverflow.com/questions" in norm_url and "stackoverflow.com/questions" in norm_expected:
        return True
    
    return False


def verify_tab_recovery(tabs_data: List[Dict], history_data: List[Tuple[str, str]]) -> Dict[str, Any]:
    """
    Perform comprehensive verification of tab recovery task.
    
    Args:
        tabs_data: List of tab information from CDP
        history_data: List of (url, title) tuples from History database
        
    Returns:
        Verification result with passed, score, and feedback
    """
    criteria_results = {}
    feedback_parts = []
    
    # Extract URLs from current tabs
    tab_urls = [tab.get('url', '') for tab in tabs_data]
    tab_titles = [tab.get('title', '') for tab in tabs_data]
    
    logger.info(f"Current tabs ({len(tabs_data)}):")
    for i, (url, title) in enumerate(zip(tab_urls, tab_titles), 1):
        logger.info(f"  Tab {i}: {url[:60]}... | {title[:40]}...")
    
    # Criterion 1: All 4 URLs were visited (History check)
    if history_data:
        history_urls = [url for url, title in history_data]
        visited_urls = {
            "wikipedia": False,
            "github": False,
            "hackernews": False,
            "stackoverflow": False
        }
        
        for key, expected_url in EXPECTED_URLS.items():
            for history_url in history_urls:
                if check_url_match(history_url, expected_url):
                    visited_urls[key] = True
                    break
        
        all_visited = all(visited_urls.values())
        criteria_results["all_visited"] = all_visited
        
        if all_visited:
            feedback_parts.append("✓ All 4 URLs were visited (Wikipedia, GitHub, Hacker News, Stack Overflow)")
        else:
            missing = [k for k, v in visited_urls.items() if not v]
            feedback_parts.append(f"✗ Not all URLs visited. Missing: {', '.join(missing)}")
        
        logger.info(f"History check: {visited_urls} -> {'PASS' if all_visited else 'FAIL'}")
    else:
        criteria_results["all_visited"] = False
        feedback_parts.append("⚠ Could not verify history (database not accessible)")
        logger.warning("History verification skipped")
    
    # Criterion 2: Exactly 3 tabs are currently open
    tab_count_correct = len(tabs_data) == 3
    criteria_results["tab_count_correct"] = tab_count_correct
    
    if tab_count_correct:
        feedback_parts.append(f"✓ Exactly 3 tabs open (correct)")
    else:
        feedback_parts.append(f"✗ Wrong tab count: {len(tabs_data)} tabs (expected 3)")
    
    logger.info(f"Tab count check: {len(tabs_data)} tabs -> {'PASS' if tab_count_correct else 'FAIL'}")
    
    # Criterion 3: Correct tabs are open (Wikipedia, GitHub, Hacker News)
    open_tabs = {
        "wikipedia": False,
        "github": False,
        "hackernews": False
    }
    
    for tab_url in tab_urls:
        for key in EXPECTED_OPEN:
            if check_url_match(tab_url, EXPECTED_URLS[key]):
                open_tabs[key] = True
    
    correct_tabs_open = all(open_tabs.values())
    criteria_results["correct_tabs_open"] = correct_tabs_open
    
    if correct_tabs_open:
        feedback_parts.append("✓ Correct tabs are open (Wikipedia, GitHub, Hacker News)")
    else:
        missing = [k for k, v in open_tabs.items() if not v]
        feedback_parts.append(f"✗ Missing expected tabs: {', '.join(missing)}")
    
    logger.info(f"Correct tabs check: {open_tabs} -> {'PASS' if correct_tabs_open else 'FAIL'}")
    
    # Criterion 4: Stack Overflow is NOT open
    stackoverflow_closed = True
    for tab_url in tab_urls:
        if check_url_match(tab_url, EXPECTED_URLS["stackoverflow"]):
            stackoverflow_closed = False
            break
    
    criteria_results["stackoverflow_closed"] = stackoverflow_closed
    
    if stackoverflow_closed:
        feedback_parts.append("✓ Stack Overflow correctly remains closed")
    else:
        feedback_parts.append("✗ Stack Overflow should not be open (should remain closed)")
    
    logger.info(f"Stack Overflow closed check: {'PASS' if stackoverflow_closed else 'FAIL'}")
    
    # Criterion 5: No duplicate tabs
    # Check for duplicate URLs among the expected research sites
    url_counts = {}
    for tab_url in tab_urls:
        for key, expected_url in EXPECTED_URLS.items():
            if check_url_match(tab_url, expected_url):
                url_counts[key] = url_counts.get(key, 0) + 1
    
    no_duplicates = all(count <= 1 for count in url_counts.values())
    criteria_results["no_duplicates"] = no_duplicates
    
    if no_duplicates:
        feedback_parts.append("✓ No duplicate tabs detected")
    else:
        duplicates = [k for k, v in url_counts.items() if v > 1]
        feedback_parts.append(f"✗ Duplicate tabs found: {', '.join(duplicates)}")
    
    logger.info(f"Duplicates check: {url_counts} -> {'PASS' if no_duplicates else 'FAIL'}")
    
    # Calculate final score
    criteria_met = sum(criteria_results.values())
    total_criteria = len(criteria_results)
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 80  # Need 4/5 criteria (80%)
    
    # Build final feedback
    feedback_parts.insert(0, f"Verification Results: {criteria_met}/{total_criteria} criteria met")
    feedback_parts.append("")
    feedback_parts.append("=" * 60)
    feedback_parts.append(f"Final Score: {score}%")
    feedback_parts.append(f"Result: {'✅ PASSED' if passed else '❌ FAILED'}")
    
    if passed:
        if score == 100:
            feedback_parts.append("Perfect execution! All tabs correctly recovered.")
        else:
            feedback_parts.append("Good job! Task completed with minor issues.")
    else:
        feedback_parts.append("Task incomplete. Please review the requirements.")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria": criteria_results,
            "tab_count": len(tabs_data),
            "tab_urls": tab_urls,
            "open_tabs": open_tabs,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
