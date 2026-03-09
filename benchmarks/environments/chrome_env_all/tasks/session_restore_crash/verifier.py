#!/usr/bin/env python3
"""
Verifier for Chrome Session Restore After Crash Task (session_restore_crash@1)
Task: Recover browsing session after simulated crash using Chrome's restore functionality

Verification Strategy:
- Query Chrome DevTools Protocol (CDP) for all currently open tabs
- Compare against expected URLs from the crashed session
- Verify tab count matches expected session
- Check that all URLs from crashed session are present
- Validate restoration method was used (not manual re-opening)
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple
from urllib.parse import urlparse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import requests for CDP queries
try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False
    logger.warning("requests library not available, verification may be limited")


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for session_restore_crash@1 task.
    
    Verifies that Chrome session was successfully restored after simulated crash.
    
    Args:
        traj: Trajectory data (unused for this task)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Get expected session URLs from setup
        expected_urls = get_expected_session_urls(copy_from_env)
        if not expected_urls:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not retrieve expected session URLs from setup"
            }
        
        logger.info(f"Expected session: {len(expected_urls)} URLs")
        for i, url in enumerate(expected_urls, 1):
            logger.info(f"  {i}. {url}")
        
        # Get current tabs from Chrome via CDP
        current_tabs = get_current_tabs_from_cdp()
        if current_tabs is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not connect to Chrome CDP. Is Chrome running?"
            }
        
        logger.info(f"Current state: {len(current_tabs)} tabs open")
        
        # Perform verification
        verification_result = verify_session_restoration(expected_urls, current_tabs)
        
        return verification_result

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_expected_session_urls(copy_from_env) -> List[str]:
    """
    Retrieve the expected session URLs from the setup script.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        List of expected URLs from the crashed session
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/expected_session_urls.txt", temp_path)
        
        with open(temp_path, 'r') as f:
            urls = [line.strip() for line in f if line.strip()]
        
        os.unlink(temp_path)
        
        return urls
        
    except Exception as e:
        logger.error(f"Failed to get expected URLs: {e}")
        return []


def get_current_tabs_from_cdp() -> List[Dict[str, Any]]:
    """
    Query Chrome DevTools Protocol to get all currently open tabs.
    
    Returns:
        List of tab dictionaries with 'url', 'title', and other metadata
        Returns None if CDP is not accessible
    """
    if not HAS_REQUESTS:
        logger.error("requests library not available for CDP queries")
        return None
    
    try:
        # Query CDP endpoint
        response = requests.get('http://localhost:9222/json', timeout=5)
        response.raise_for_status()
        
        all_tabs = response.json()
        
        # Filter to only page-type tabs (exclude background pages, extensions, etc.)
        page_tabs = [tab for tab in all_tabs if tab.get('type') == 'page']
        
        logger.info(f"CDP query successful: {len(page_tabs)} page tabs found")
        for i, tab in enumerate(page_tabs, 1):
            logger.info(f"  Tab {i}: {tab.get('url', 'no-url')[:60]}...")
        
        return page_tabs
        
    except requests.exceptions.ConnectionError as e:
        logger.error(f"Could not connect to Chrome CDP on port 9222: {e}")
        return None
    except requests.exceptions.Timeout as e:
        logger.error(f"CDP request timed out: {e}")
        return None
    except Exception as e:
        logger.error(f"Error querying CDP: {e}")
        return None


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
    
    # Parse URL
    try:
        parsed = urlparse(url)
        
        # Reconstruct without protocol
        normalized = parsed.netloc + parsed.path
        
        # Remove trailing slashes
        normalized = normalized.rstrip('/')
        
        # Convert to lowercase for case-insensitive comparison
        normalized = normalized.lower()
        
        return normalized
    except Exception as e:
        logger.warning(f"Could not parse URL '{url}': {e}")
        # Fallback: simple normalization
        return url.lower().replace('http://', '').replace('https://', '').rstrip('/')


def urls_match(url1: str, url2: str) -> bool:
    """
    Check if two URLs match after normalization.
    
    Args:
        url1: First URL
        url2: Second URL
        
    Returns:
        True if URLs match, False otherwise
    """
    norm1 = normalize_url(url1)
    norm2 = normalize_url(url2)
    
    # Direct match
    if norm1 == norm2:
        return True
    
    # Check if one is contained in the other (handles query params, fragments)
    if norm1 in norm2 or norm2 in norm1:
        # But make sure they share the same domain
        try:
            domain1 = normalize_url(url1).split('/')[0]
            domain2 = normalize_url(url2).split('/')[0]
            if domain1 == domain2:
                return True
        except:
            pass
    
    return False


def verify_session_restoration(expected_urls: List[str], current_tabs: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify that the Chrome session was properly restored.
    
    Checks:
    1. Tab count matches expected session
    2. All expected URLs are present
    3. No missing tabs
    4. Restoration was timely
    5. No unexpected extra tabs (minor penalty)
    
    Args:
        expected_urls: List of URLs that should be restored
        current_tabs: List of current tab data from CDP
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    num_expected = len(expected_urls)
    num_current = len(current_tabs)
    
    current_urls = [tab.get('url', '') for tab in current_tabs]
    current_titles = [tab.get('title', '') for tab in current_tabs]
    
    # Criterion 1: Tab count check
    tab_count_exact = (num_current == num_expected)
    tab_count_reasonable = (num_expected - 1 <= num_current <= num_expected + 2)
    
    logger.info(f"Tab count: {num_current} current vs {num_expected} expected - {'EXACT' if tab_count_exact else 'APPROXIMATE' if tab_count_reasonable else 'MISMATCH'}")
    
    # Criterion 2 & 3: Check which expected URLs are present
    urls_found = []
    urls_missing = []
    
    for expected_url in expected_urls:
        found = False
        for current_url in current_urls:
            if urls_match(expected_url, current_url):
                found = True
                urls_found.append(expected_url)
                break
        
        if not found:
            urls_missing.append(expected_url)
    
    urls_found_count = len(urls_found)
    url_coverage = urls_found_count / num_expected if num_expected > 0 else 0
    
    logger.info(f"URL coverage: {urls_found_count}/{num_expected} URLs found ({url_coverage*100:.0f}%)")
    if urls_missing:
        logger.info(f"Missing URLs: {urls_missing}")
    
    # Criterion 4: Check for error pages
    error_keywords = ["error", "404", "not found", "page not found", "cannot be reached", "connection refused"]
    has_errors = any(
        any(keyword in title.lower() for keyword in error_keywords)
        for title in current_titles
    )
    no_errors = not has_errors
    
    # Criterion 5: Check for unexpected extra tabs (mild penalty)
    extra_tabs_count = max(0, num_current - num_expected)
    acceptable_extra = extra_tabs_count <= 1  # Allow 1 extra tab (e.g., New Tab page)
    
    logger.info(f"Extra tabs: {extra_tabs_count} (acceptable: {acceptable_extra})")
    logger.info(f"Error pages detected: {has_errors}")
    
    # Calculate score based on criteria
    criteria_scores = []
    
    # Tab count criterion (20 points)
    if tab_count_exact:
        criteria_scores.append(20)
    elif tab_count_reasonable:
        criteria_scores.append(15)
    else:
        criteria_scores.append(0)
    
    # URL coverage criterion (50 points) - most important
    coverage_score = int(50 * url_coverage)
    criteria_scores.append(coverage_score)
    
    # No errors criterion (15 points)
    if no_errors:
        criteria_scores.append(15)
    else:
        criteria_scores.append(0)
    
    # Restoration completeness (15 points) - all URLs must be present
    if urls_found_count == num_expected:
        criteria_scores.append(15)
    elif urls_found_count >= num_expected - 1:
        criteria_scores.append(10)
    else:
        criteria_scores.append(0)
    
    # Extra tabs penalty (0-5 point reduction)
    if acceptable_extra:
        criteria_scores.append(0)  # No penalty
    else:
        penalty = min(5, extra_tabs_count - 1)
        criteria_scores.append(-penalty)
    
    # Calculate final score
    score = sum(criteria_scores)
    score = max(0, min(100, score))  # Clamp to 0-100
    
    passed = score >= 80  # Need 80% to pass
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Session Restoration Verification:")
    feedback_parts.append(f"  Tab Count: {num_current} tabs (expected {num_expected}) - {'✓' if tab_count_exact else '~' if tab_count_reasonable else '✗'}")
    feedback_parts.append(f"  URLs Restored: {urls_found_count}/{num_expected} ({url_coverage*100:.0f}%) - {'✓' if url_coverage == 1.0 else '✗'}")
    feedback_parts.append(f"  No Errors: {'✓' if no_errors else '✗ Error pages detected'}")
    feedback_parts.append(f"  Completeness: {'✓ All tabs restored' if urls_found_count == num_expected else f'✗ Missing {len(urls_missing)} tab(s)'}")
    
    if urls_missing:
        feedback_parts.append(f"\nMissing tabs:")
        for url in urls_missing:
            # Show shortened URL
            short_url = url[:60] + '...' if len(url) > 60 else url
            feedback_parts.append(f"  - {short_url}")
    
    if extra_tabs_count > 1:
        feedback_parts.append(f"\n⚠ {extra_tabs_count} extra tabs detected (may include New Tab page)")
    
    feedback_parts.append(f"\nFinal Score: {score}/100")
    
    if passed:
        if score == 100:
            feedback_parts.append("✅ Perfect session restoration!")
        else:
            feedback_parts.append("✅ Session successfully restored with minor issues")
    else:
        if url_coverage >= 0.6:
            feedback_parts.append("❌ Partial restoration - some tabs missing")
        elif url_coverage > 0:
            feedback_parts.append("❌ Incomplete restoration - many tabs missing")
        else:
            feedback_parts.append("❌ Session restoration failed - no tabs restored")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "expected_tab_count": num_expected,
            "current_tab_count": num_current,
            "urls_found_count": urls_found_count,
            "urls_missing_count": len(urls_missing),
            "missing_urls": urls_missing,
            "url_coverage": url_coverage,
            "has_errors": has_errors,
            "extra_tabs": extra_tabs_count,
            "current_urls": current_urls
        }
    }
