#!/usr/bin/env python3
"""
Verifier for Chrome multi-tab session task
Checks that 4 specific tabs are open using Chrome DevTools Protocol
"""

import sys
import re
import time
import logging
from typing import Dict, Any, List, Tuple

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import requests, provide fallback
try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    logger.warning("requests module not available, using urllib fallback")
    HAS_REQUESTS = False
    import urllib.request
    import json as json_module


def get_chrome_tabs_via_cdp(cdp_port: int = 9222, max_retries: int = 3) -> List[Dict[str, Any]]:
    """
    Query Chrome DevTools Protocol for all open tabs.
    
    Args:
        cdp_port: CDP port number (default 9222)
        max_retries: Maximum number of retry attempts
        
    Returns:
        List of tab dictionaries with url, title, type, id
    """
    url = f'http://localhost:{cdp_port}/json'
    
    for attempt in range(max_retries):
        try:
            if HAS_REQUESTS:
                response = requests.get(url, timeout=5)
                response.raise_for_status()
                tabs = response.json()
            else:
                # Fallback using urllib
                with urllib.request.urlopen(url, timeout=5) as response:
                    tabs = json_module.loads(response.read().decode())
            
            # Filter to only 'page' type (excludes background pages, extensions, etc.)
            page_tabs = [tab for tab in tabs if tab.get('type') == 'page']
            logger.info(f"Retrieved {len(page_tabs)} page tabs from CDP")
            return page_tabs
            
        except Exception as e:
            logger.warning(f"Attempt {attempt + 1}/{max_retries} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(1)
            else:
                logger.error(f"Failed to get Chrome tabs after {max_retries} attempts")
                return []
    
    return []


def verify_url_pattern(url: str, pattern: str) -> bool:
    """
    Check if URL matches expected regex pattern (case insensitive).
    
    Args:
        url: URL string to check
        pattern: Regex pattern to match
        
    Returns:
        True if URL matches pattern
    """
    try:
        return bool(re.search(pattern, url, re.IGNORECASE))
    except Exception as e:
        logger.error(f"Error matching pattern '{pattern}' against '{url}': {e}")
        return False


def check_for_error_pages(tabs: List[Dict[str, Any]]) -> Tuple[bool, List[str]]:
    """
    Check if any tabs are showing Chrome error pages.
    
    Returns:
        Tuple of (has_errors, list of error URLs)
    """
    error_patterns = [
        r'chrome-error://',
        r'chrome://network-error/',
        r'data:text/html,chromewebdata',
    ]
    
    error_urls = []
    for tab in tabs:
        url = tab.get('url', '')
        for pattern in error_patterns:
            if re.search(pattern, url, re.IGNORECASE):
                error_urls.append(url)
                break
    
    return len(error_urls) > 0, error_urls


def verify_multi_tab_session(traj, env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that exactly 4 tabs are open with correct URLs:
    - Wikipedia (en.wikipedia.org)
    - GitHub (github.com)
    - Stack Overflow (stackoverflow.com)
    - MDN Web Docs (developer.mozilla.org)
    
    Args:
        traj: Trajectory information (unused for this verifier)
        env_info: Environment information
        task_info: Task information
        
    Returns:
        Dictionary with passed, score, and feedback
    """
    logger.info("Starting multi-tab session verification...")
    
    # Required URL patterns and their display names
    required_patterns = {
        'wikipedia': {
            'pattern': r'.*wikipedia\.org.*',
            'display': 'Wikipedia',
            'urls': ['https://en.wikipedia.org', 'https://www.wikipedia.org']
        },
        'github': {
            'pattern': r'.*github\.com.*',
            'display': 'GitHub',
            'urls': ['https://github.com', 'https://www.github.com']
        },
        'stackoverflow': {
            'pattern': r'.*stackoverflow\.com.*',
            'display': 'Stack Overflow',
            'urls': ['https://stackoverflow.com', 'https://www.stackoverflow.com']
        },
        'mdn': {
            'pattern': r'.*(developer\.mozilla\.org|mdn\.mozilla\.org).*',
            'display': 'MDN Web Docs',
            'urls': ['https://developer.mozilla.org', 'https://developer.mozilla.org/en-US/']
        }
    }
    
    # Get CDP port from environment info or use default
    cdp_port = env_info.get('cdp_port', 9222)
    
    # Get all open tabs
    tabs = get_chrome_tabs_via_cdp(cdp_port)
    
    if not tabs:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to retrieve Chrome tabs via CDP. Ensure Chrome is running with remote debugging enabled."
        }
    
    # Check for error pages
    has_errors, error_urls = check_for_error_pages(tabs)
    if has_errors:
        logger.warning(f"Found {len(error_urls)} error pages: {error_urls}")
    
    # Extract URLs from tabs
    tab_urls = [tab.get('url', '') for tab in tabs]
    tab_titles = [tab.get('title', 'Untitled') for tab in tabs]
    
    logger.info(f"Found {len(tab_urls)} tabs total")
    for i, (url, title) in enumerate(zip(tab_urls, tab_titles)):
        logger.info(f"  Tab {i+1}: {url[:80]}... | {title[:50]}")
    
    # Check which required tabs are present
    found = {name: False for name in required_patterns.keys()}
    matched_urls = {name: None for name in required_patterns.keys()}
    
    for name, info in required_patterns.items():
        pattern = info['pattern']
        for url in tab_urls:
            if verify_url_pattern(url, pattern):
                found[name] = True
                matched_urls[name] = url
                logger.info(f"✓ Found {info['display']}: {url}")
                break
    
    # Count how many required tabs were found
    tabs_found = sum(found.values())
    total_tabs = len(tab_urls)
    required_count = len(required_patterns)
    
    # Calculate score
    # 100% for all 4 correct tabs and no extra tabs
    # Deduct points for missing tabs
    # Deduct points for extra tabs
    if tabs_found == required_count and total_tabs == required_count:
        score = 100
    elif tabs_found == required_count and total_tabs <= required_count + 1:
        # All required tabs but 1 extra tab
        score = 90
    elif tabs_found == required_count and total_tabs > required_count + 1:
        # All required tabs but multiple extra tabs
        score = 80
    elif tabs_found == 3:
        # 3 out of 4 required tabs
        score = 75
    elif tabs_found == 2:
        # 2 out of 4 required tabs
        score = 50
    elif tabs_found == 1:
        # 1 out of 4 required tabs
        score = 25
    else:
        # No required tabs found
        score = 0
    
    # Determine pass/fail (need at least 75%)
    passed = score >= 75
    
    # Build detailed feedback
    feedback_lines = [
        f"Multi-tab session verification:",
        f"  Required tabs: {required_count}",
        f"  Tabs found: {tabs_found}/{required_count}",
        f"  Total open tabs: {total_tabs}",
        ""
    ]
    
    # List each required tab and its status
    for name, info in required_patterns.items():
        status = "✓ FOUND" if found[name] else "✗ MISSING"
        feedback_lines.append(f"  {status}: {info['display']}")
        if found[name] and matched_urls[name]:
            feedback_lines.append(f"    → {matched_urls[name]}")
    
    feedback_lines.append("")
    
    # Add scoring explanation
    if passed:
        if score == 100:
            feedback_lines.append("Perfect! All 4 required tabs open with no extra tabs.")
        elif score >= 75:
            if tabs_found == required_count:
                feedback_lines.append(f"Good! All required tabs present, but {total_tabs - required_count} extra tab(s) open.")
            else:
                feedback_lines.append(f"Good! {tabs_found} out of {required_count} required tabs present.")
    else:
        missing_count = required_count - tabs_found
        feedback_lines.append(f"Failed: {missing_count} required tab(s) missing.")
        
        # List what's missing
        missing_tabs = [info['display'] for name, info in required_patterns.items() if not found[name]]
        if missing_tabs:
            feedback_lines.append(f"Missing: {', '.join(missing_tabs)}")
        
        # Give hints on what to do
        feedback_lines.append("")
        feedback_lines.append("To complete this task:")
        feedback_lines.append("1. Press Ctrl+T to open a new tab")
        feedback_lines.append("2. Type the URL in the address bar")
        feedback_lines.append("3. Press Enter to navigate")
        feedback_lines.append("4. Repeat for all required URLs")
    
    # Add warning about error pages
    if has_errors:
        feedback_lines.append("")
        feedback_lines.append(f"⚠ Warning: {len(error_urls)} tab(s) showing error pages (network issues?)")
    
    feedback = "\n".join(feedback_lines)
    
    logger.info(f"Verification result: {'PASSED' if passed else 'FAILED'} (score: {score}%)")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "tabs_found": tabs_found,
            "required_tabs": required_count,
            "total_tabs": total_tabs,
            "found_details": found,
            "matched_urls": matched_urls,
            "has_error_pages": has_errors
        }
    }
