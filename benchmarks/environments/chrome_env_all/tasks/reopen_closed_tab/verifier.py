#!/usr/bin/env python3
"""
Verifier for Chrome Reopen Closed Tab Task: reopen_closed_tab@1
Task: Recover accidentally closed tab using Ctrl+Shift+T or menu

Verification Strategy:
- Read the target URL that was closed during setup
- Query current open tabs via CDP
- Check if the target URL is now present in open tabs
- Validate that recovery happened (not just navigation to URL)
- Ensure no duplicates or errors
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from urllib.parse import urlparse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for reopen_closed_tab@1 task.
    
    Verifies that the accidentally closed tab was successfully reopened.
    
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
        # Get target URL that was closed
        target_url = get_target_url(copy_from_env)
        if not target_url:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not determine which tab was closed (setup may have failed)"
            }
        
        logger.info(f"Target URL to verify: {target_url}")
        
        # Get current tabs from CDP
        current_tabs = get_current_tabs(copy_from_env)
        if current_tabs is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve current tab information from Chrome"
            }
        
        # Verify tab was recovered
        verification_result = verify_tab_recovery(target_url, current_tabs)
        
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


def get_target_url(copy_from_env):
    """
    Get the target URL that was closed from setup.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        str: Target URL or None if not found
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        
        copy_from_env("/tmp/closed_tab_url.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            target_url = f.read().strip()
        
        os.unlink(temp_file.name)
        
        return target_url
        
    except Exception as e:
        logger.error(f"Failed to get target URL: {e}")
        return None


def get_current_tabs(copy_from_env):
    """
    Get current open tabs from CDP data.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        List of tab dicts or None if failed
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        
        copy_from_env("/tmp/chrome_page_tabs_final.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            tabs_data = json.load(f)
        
        os.unlink(temp_file.name)
        
        logger.info(f"Retrieved {len(tabs_data)} tab(s) from CDP")
        
        return tabs_data
        
    except Exception as e:
        logger.error(f"Failed to get current tabs: {e}")
        return None


def normalize_url(url):
    """
    Normalize URL for comparison.
    
    Args:
        url: URL string
        
    Returns:
        Normalized URL string
    """
    if not url:
        return ""
    
    # Parse URL
    parsed = urlparse(url)
    
    # Reconstruct without query/fragment for main comparison
    normalized = f"{parsed.scheme}://{parsed.netloc}{parsed.path}"
    
    # Remove trailing slashes
    normalized = normalized.rstrip('/')
    
    # Convert to lowercase
    normalized = normalized.lower()
    
    return normalized


def verify_tab_recovery(target_url, current_tabs):
    """
    Verify that the target tab was successfully recovered.
    
    Checks:
    1. Target URL is present in current tabs
    2. Tab has valid title (not error page)
    3. No duplicate instances of target URL
    4. Reasonable total tab count
    
    Args:
        target_url: The URL that should have been recovered
        current_tabs: List of current tab data from CDP
        
    Returns:
        Dict with verification results
    """
    # Normalize target URL
    target_normalized = normalize_url(target_url)
    logger.info(f"Normalized target: {target_normalized}")
    
    # Extract current tab URLs
    current_urls = [tab.get('url', '') for tab in current_tabs]
    current_titles = [tab.get('title', '') for tab in current_tabs]
    
    logger.info(f"Current tabs ({len(current_tabs)}):")
    for i, (url, title) in enumerate(zip(current_urls, current_titles), 1):
        logger.info(f"  Tab {i}: {url[:60]}... | {title[:40]}...")
    
    # Criterion 1: Target URL is present
    target_found = False
    target_title = ""
    matches_count = 0
    
    for tab in current_tabs:
        tab_url = tab.get('url', '')
        tab_url_normalized = normalize_url(tab_url)
        
        if target_normalized in tab_url_normalized or tab_url_normalized in target_normalized:
            target_found = True
            target_title = tab.get('title', '')
            matches_count += 1
            logger.info(f"✓ Found target URL: {tab_url}")
    
    # Criterion 2: Valid title (not error page)
    error_keywords = ["error", "404", "not found", "cannot be reached", "problem loading"]
    has_valid_title = True
    
    if target_found and target_title:
        title_lower = target_title.lower()
        if any(keyword in title_lower for keyword in error_keywords):
            has_valid_title = False
            logger.warning(f"✗ Error detected in title: {target_title}")
    
    # Criterion 3: No duplicate target URLs
    no_duplicates = (matches_count <= 1)
    if matches_count > 1:
        logger.warning(f"✗ Found {matches_count} instances of target URL (expected 1)")
    
    # Criterion 4: Reasonable tab count (should have multiple tabs)
    reasonable_tab_count = 2 <= len(current_tabs) <= 10
    if not reasonable_tab_count:
        logger.warning(f"✗ Unusual tab count: {len(current_tabs)}")
    
    # Calculate score
    criteria = [
        target_found,
        has_valid_title,
        no_duplicates,
        reasonable_tab_count
    ]
    
    criteria_met = sum(criteria)
    score = (criteria_met / len(criteria)) * 100
    passed = target_found and score >= 75  # Must have target URL + at least 3/4 criteria
    
    # Generate feedback
    feedback_parts = []
    feedback_parts.append(f"Target URL: {target_url}")
    feedback_parts.append(f"Verification Results: {criteria_met}/{len(criteria)} criteria met")
    feedback_parts.append(f"")
    feedback_parts.append(f"1. Target URL present: {'✓' if target_found else '✗'}")
    
    if not target_found:
        feedback_parts.append(f"   The tab with URL '{target_url}' was not found in open tabs.")
        feedback_parts.append(f"   Did you press Ctrl+Shift+T to reopen the closed tab?")
    else:
        feedback_parts.append(f"   Found: {target_title[:60]}")
    
    feedback_parts.append(f"2. Valid title (no errors): {'✓' if has_valid_title else '✗'}")
    feedback_parts.append(f"3. No duplicate tabs: {'✓' if no_duplicates else '✗'}")
    
    if not no_duplicates:
        feedback_parts.append(f"   Found {matches_count} instances (expected 1)")
    
    feedback_parts.append(f"4. Reasonable tab count: {'✓' if reasonable_tab_count else '✗'} ({len(current_tabs)} tabs)")
    
    feedback_parts.append(f"")
    
    if passed:
        feedback_parts.append("✅ Tab successfully recovered! Task completed.")
    elif target_found:
        feedback_parts.append("⚠ Tab found but with minor issues.")
    else:
        feedback_parts.append("❌ Tab was not recovered. Try pressing Ctrl+Shift+T to reopen.")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": {
            "target_url": target_url,
            "target_found": target_found,
            "target_title": target_title,
            "matches_count": matches_count,
            "total_tabs": len(current_tabs),
            "criteria_met": criteria_met,
            "current_urls": current_urls[:5]  # First 5 for debugging
        }
    }
