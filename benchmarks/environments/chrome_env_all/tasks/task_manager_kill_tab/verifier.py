#!/usr/bin/env python3
"""
Verifier for Chrome Task Manager Process Management Task: task_manager_kill_tab@1
Task: Use Chrome Task Manager to kill GitHub tab while preserving other tabs

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) to query all open tabs
- Verifies exactly 3 tabs remain (not 4)
- Checks that github.com is NOT present
- Validates that example.com, wikipedia.org, and stackoverflow.com ARE present
- Ensures browser is still responsive (didn't crash)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any

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
    Main verification function for task_manager_kill_tab@1 task.
    
    Verifies that the GitHub tab was killed via Task Manager while preserving other tabs.
    
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
        verification_result = verify_task_manager_usage(tabs_data)
        
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
        
        # Try to copy from the export location
        copy_from_env("/tmp/chrome_page_tabs_final.json", temp_path)
        
        if not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
            logger.error("Tab data file is empty or missing")
            return None
        
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
    Normalize URL for comparison by removing protocol, www, and trailing slashes.
    
    Args:
        url: URL string to normalize
        
    Returns:
        Normalized URL string
    """
    if not url:
        return ""
    
    url_lower = url.lower()
    # Remove protocol
    url_lower = url_lower.replace('https://', '').replace('http://', '')
    # Remove www
    url_lower = url_lower.replace('www.', '')
    # Remove trailing slash
    url_lower = url_lower.rstrip('/')
    
    return url_lower


def check_url_contains(url: str, domain: str) -> bool:
    """
    Check if URL contains a specific domain.
    
    Args:
        url: Full URL to check
        domain: Domain to search for (e.g., "github.com")
        
    Returns:
        True if domain is found in URL
    """
    url_normalized = normalize_url(url)
    domain_normalized = normalize_url(domain)
    
    return domain_normalized in url_normalized


def verify_task_manager_usage(tabs_data: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify that Task Manager was used to kill GitHub tab.
    
    Checks 4 criteria:
    1. Exactly 3 tabs remain (not 4)
    2. GitHub tab is NOT present
    3. All 3 expected tabs ARE present (example.com, wikipedia.org, stackoverflow.com)
    4. Browser is still responsive (tabs have valid data)
    
    Args:
        tabs_data: List of tab information from CDP
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    # Extract URLs from tabs
    tab_urls = [tab.get('url', '') for tab in tabs_data]
    tab_titles = [tab.get('title', '') for tab in tabs_data]
    
    logger.info(f"Found {len(tabs_data)} tabs in final state")
    for i, (url, title) in enumerate(zip(tab_urls, tab_titles), 1):
        logger.info(f"  Tab {i}: {url[:60]}... | {title[:50]}...")
    
    # Criterion 1: Exactly 3 tabs remain
    correct_tab_count = len(tabs_data) == 3
    logger.info(f"Criterion 1 - Tab count: {len(tabs_data)} (expected 3) - {'PASS' if correct_tab_count else 'FAIL'}")
    
    # Criterion 2: GitHub tab is NOT present
    github_present = any(check_url_contains(url, "github.com") for url in tab_urls)
    github_closed = not github_present
    logger.info(f"Criterion 2 - GitHub closed: {github_closed} (GitHub present: {github_present}) - {'PASS' if github_closed else 'FAIL'}")
    
    # Criterion 3: Expected tabs ARE present
    example_present = any(check_url_contains(url, "example.com") for url in tab_urls)
    wikipedia_present = any(check_url_contains(url, "wikipedia.org") for url in tab_urls)
    stackoverflow_present = any(check_url_contains(url, "stackoverflow.com") for url in tab_urls)
    
    expected_tabs_present = example_present and wikipedia_present and stackoverflow_present
    logger.info(f"Criterion 3 - Expected tabs present:")
    logger.info(f"  - example.com: {example_present}")
    logger.info(f"  - wikipedia.org: {wikipedia_present}")
    logger.info(f"  - stackoverflow.com: {stackoverflow_present}")
    logger.info(f"  - All present: {expected_tabs_present} - {'PASS' if expected_tabs_present else 'FAIL'}")
    
    # Criterion 4: Browser responsive (has valid tab data)
    browser_responsive = len(tabs_data) > 0 and all(
        tab.get('url') and tab.get('title') for tab in tabs_data
    )
    logger.info(f"Criterion 4 - Browser responsive: {browser_responsive} - {'PASS' if browser_responsive else 'FAIL'}")
    
    # Calculate score based on criteria met
    criteria_results = [
        correct_tab_count,
        github_closed,
        expected_tabs_present,
        browser_responsive
    ]
    
    criteria_met = sum(criteria_results)
    score = (criteria_met / 4.0) * 100
    passed = score >= 75  # Need at least 3/4 criteria (75%)
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Task Manager Process Management Verification")
    feedback_parts.append(f"{'='*50}")
    feedback_parts.append(f"Criteria met: {criteria_met}/4")
    feedback_parts.append(f"")
    
    # Detailed criterion feedback
    if correct_tab_count:
        feedback_parts.append(f"✓ Tab count correct: {len(tabs_data)} tabs (GitHub tab successfully killed)")
    else:
        feedback_parts.append(f"✗ Tab count incorrect: {len(tabs_data)} tabs (expected 3)")
        if len(tabs_data) == 4:
            feedback_parts.append(f"  Hint: GitHub tab was not killed - use Shift+Esc to open Task Manager")
        elif len(tabs_data) < 3:
            feedback_parts.append(f"  Warning: Too few tabs - other tabs may have been closed")
        else:
            feedback_parts.append(f"  Warning: Too many tabs - extra tabs were opened")
    
    if github_closed:
        feedback_parts.append(f"✓ GitHub tab successfully terminated")
    else:
        feedback_parts.append(f"✗ GitHub tab still present - it was not killed")
        feedback_parts.append(f"  Task requirement: End the github.com process via Task Manager")
    
    if expected_tabs_present:
        feedback_parts.append(f"✓ All expected tabs preserved (example, wikipedia, stackoverflow)")
    else:
        feedback_parts.append(f"✗ Some expected tabs are missing:")
        if not example_present:
            feedback_parts.append(f"  - example.com tab missing")
        if not wikipedia_present:
            feedback_parts.append(f"  - wikipedia.org tab missing")
        if not stackoverflow_present:
            feedback_parts.append(f"  - stackoverflow.com tab missing")
    
    if browser_responsive:
        feedback_parts.append(f"✓ Browser remains responsive (no crash)")
    else:
        feedback_parts.append(f"✗ Browser may have crashed or tabs have invalid data")
    
    feedback_parts.append(f"")
    feedback_parts.append(f"Score: {int(score)}/100")
    
    if passed:
        feedback_parts.append(f"")
        feedback_parts.append(f"✅ TASK PASSED - GitHub tab killed via Task Manager!")
    else:
        feedback_parts.append(f"")
        feedback_parts.append(f"❌ TASK FAILED - Requirements not met")
        if not github_closed and len(tabs_data) == 4:
            feedback_parts.append(f"")
            feedback_parts.append(f"Hint: Use Shift+Esc to open Chrome Task Manager,")
            feedback_parts.append(f"      find the GitHub tab process, and click 'End process'")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": {
            "tab_count": len(tabs_data),
            "criteria_met": criteria_met,
            "github_closed": github_closed,
            "expected_tabs_present": {
                "example.com": example_present,
                "wikipedia.org": wikipedia_present,
                "stackoverflow.com": stackoverflow_present
            },
            "browser_responsive": browser_responsive,
            "final_tab_urls": tab_urls
        }
    }
