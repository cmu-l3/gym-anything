#!/usr/bin/env python3
"""
Verifier for Chrome View Page Source Task (view_source_search@1)
Task: View webpage HTML source code using Chrome's view source feature

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) to query all open tabs
- Checks if any tab has URL starting with "view-source:"
- Verifies the source view is for the expected target page
- Validates that source view is active (bonus points)
- Optionally detects if search was used (aspirational)
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from urllib.parse import urlparse
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


def verify_task(traj, env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Main verification function for view_source_search@1 task.
    
    Verifies:
    1. Source view tab exists (view-source: URL prefix)
    2. Source view is for the correct target page
    3. Source view tab is active (bonus)
    4. Total tab count is reasonable (2 tabs: original + source)
    
    Scoring:
    - 100%: Source view active for correct page
    - 90%: Source view exists for correct page but not active
    - 75%: Source view exists but for slightly wrong page variant
    - 50%: Source view exists but for completely wrong page
    - 0-40%: No source view tab detected
    
    Pass threshold: 75% (requires source view for correct page)
    
    Args:
        traj: Trajectory data (not used for CDP-based verification)
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

        # Perform verification
        verification_result = verify_source_view_task(tabs_data, task_info)
        
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


def get_tabs_data(copy_from_env) -> Optional[List[Dict[str, Any]]]:
    """
    Retrieve tab information from container using CDP data.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        List of tab dictionaries with 'url', 'title', and metadata, or None on failure
    """
    try:
        # Copy the CDP JSON data from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try to get page tabs data
        copy_from_env("/tmp/chrome_page_tabs.json", temp_path)
        
        with open(temp_path, 'r') as f:
            tabs_data = json.load(f)
        
        os.unlink(temp_path)
        
        logger.info(f"Successfully retrieved {len(tabs_data)} tab(s) from CDP")
        return tabs_data
        
    except Exception as e:
        logger.error(f"Failed to get tabs data: {e}")
        return None


def normalize_url_for_comparison(url: str) -> str:
    """
    Normalize URL for comparison, removing protocol, trailing slashes, query params, etc.
    
    Args:
        url: URL string to normalize
        
    Returns:
        Normalized URL string
    """
    if not url:
        return ""
    
    # Remove view-source: prefix if present
    url = re.sub(r'^view-source:', '', url)
    
    # Parse URL
    parsed = urlparse(url)
    
    # Normalize: lowercase domain, remove trailing slash, ignore query params
    domain = parsed.netloc.lower()
    path = parsed.path.rstrip('/')
    
    return f"{domain}{path}"


def verify_source_view_task(tabs_data: List[Dict[str, Any]], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that page source was correctly viewed.
    
    Checks:
    1. At least one tab has "view-source:" URL prefix
    2. The source view is for the expected target page (Wikipedia Web Browser article)
    3. Source view tab is the active tab (bonus)
    4. Tab count is reasonable (original + source = 2)
    
    Args:
        tabs_data: List of tab information from CDP
        task_info: Task configuration
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    # Expected target page
    expected_domain = "en.wikipedia.org"
    expected_path_keywords = ["web_browser", "web browser"]
    
    # Extract all URLs
    tab_urls = [tab.get('url', '') for tab in tabs_data]
    tab_titles = [tab.get('title', '') for tab in tabs_data]
    
    logger.info(f"Found {len(tabs_data)} tabs total")
    for i, (url, title) in enumerate(zip(tab_urls, tab_titles), 1):
        logger.info(f"  Tab {i}: {url[:80]}... | Title: {title[:50]}...")
    
    # Criterion 1: Check for view-source: tabs
    source_view_tabs = []
    for i, tab in enumerate(tabs_data):
        url = tab.get('url', '')
        if url.startswith('view-source:'):
            source_view_tabs.append((i, tab))
    
    if not source_view_tabs:
        logger.info("✗ No view-source: tabs found")
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "❌ No source view tab found. To complete this task:\n"
                "  1. Press Ctrl+U while on the Wikipedia page, OR\n"
                "  2. Right-click on the page and select 'View page source'\n"
                "The source code should open in a new tab with 'view-source:' in the URL."
            ),
            "details": {
                "source_view_found": False,
                "tab_count": len(tabs_data),
                "tab_urls": tab_urls
            }
        }
    
    logger.info(f"✓ Found {len(source_view_tabs)} view-source tab(s)")
    
    # Get the first source view tab
    source_tab_index, source_tab = source_view_tabs[0]
    source_url = source_tab.get('url', '')
    source_title = source_tab.get('title', '')
    
    # Extract the original URL from view-source:
    original_url = source_url.replace('view-source:', '', 1)
    normalized_original = normalize_url_for_comparison(original_url)
    
    logger.info(f"Source view URL: {source_url}")
    logger.info(f"Original URL: {original_url}")
    logger.info(f"Normalized: {normalized_original}")
    
    # Criterion 2: Verify it's for the correct page
    correct_domain = expected_domain in normalized_original
    correct_path = any(keyword.lower().replace(' ', '_') in normalized_original.lower() 
                       for keyword in expected_path_keywords)
    
    correct_page = correct_domain and correct_path
    
    if not correct_domain:
        logger.info(f"✗ Wrong domain: expected {expected_domain}, got {normalized_original}")
        return {
            "passed": False,
            "score": 40,
            "feedback": (
                f"⚠ Source view opened for wrong website.\n"
                f"Expected: Wikipedia (en.wikipedia.org)\n"
                f"Got: {original_url}\n"
                f"Please view source for the Wikipedia 'Web Browser' article."
            ),
            "details": {
                "source_view_found": True,
                "correct_page": False,
                "source_url": source_url,
                "expected_domain": expected_domain
            }
        }
    
    if not correct_path:
        logger.info(f"✗ Wrong Wikipedia page: expected 'Web_browser' article")
        return {
            "passed": False,
            "score": 50,
            "feedback": (
                f"⚠ Source view opened for different Wikipedia page.\n"
                f"Expected: Web Browser article\n"
                f"Got: {original_url}\n"
                f"Please navigate to the correct article first."
            ),
            "details": {
                "source_view_found": True,
                "correct_page": False,
                "source_url": source_url
            }
        }
    
    logger.info("✓ Source view is for correct page")
    
    # Criterion 3: Check if source view is active (first tab in list)
    # CDP typically returns active/most-recent tabs first
    is_active = source_tab_index == 0
    
    logger.info(f"✓ Source view active: {is_active} (index: {source_tab_index})")
    
    # Criterion 4: Check tab count is reasonable
    reasonable_tab_count = 1 <= len(tabs_data) <= 3
    
    logger.info(f"✓ Tab count check: {len(tabs_data)} tabs ({'reasonable' if reasonable_tab_count else 'unusual'})")
    
    # Calculate score
    if is_active and correct_page and reasonable_tab_count:
        score = 100
        feedback_intro = "✅ Task completed perfectly!"
    elif correct_page and reasonable_tab_count:
        score = 90
        feedback_intro = "✅ Task completed successfully!"
    elif correct_page:
        score = 75
        feedback_intro = "✅ Task completed (source view found for correct page)"
    else:
        score = 50
        feedback_intro = "⚠ Partial success"
    
    passed = score >= 75
    
    # Generate detailed feedback
    feedback_parts = [feedback_intro]
    feedback_parts.append(f"✓ Source view tab detected: {source_url}")
    feedback_parts.append(f"✓ Correct page: Wikipedia Web Browser article")
    feedback_parts.append(f"✓ Active tab: {'Yes' if is_active else 'No (source tab exists but not focused)'}")
    feedback_parts.append(f"  Total tabs: {len(tabs_data)}")
    
    if not is_active and score >= 75:
        feedback_parts.append("  Hint: Click on the source view tab to make it active for full marks")
    
    feedback_parts.append("\n💡 Pro tip: You can press Ctrl+F to search for keywords like 'viewport', 'charset', or 'meta' in the source code!")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "source_view_found": True,
            "correct_page": correct_page,
            "is_active": is_active,
            "tab_count": len(tabs_data),
            "source_url": source_url,
            "source_title": source_title,
            "tab_urls": tab_urls
        }
    }
