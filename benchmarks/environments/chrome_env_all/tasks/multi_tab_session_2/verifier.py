#!/usr/bin/env python3
"""
Verifier for Chrome Multi-Tab Session Task: multi_tab_session@1
Task: Open 4 tabs with Wikipedia, GitHub, Stack Overflow, and MDN Web Docs

Verification Strategy:
- Use Chrome DevTools Protocol (CDP) to enumerate all open tabs
- Check that exactly 4 tabs are open
- Verify each required URL pattern is present in the tab list
- Score based on number of correct tabs found
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import List, Dict, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path for potential future use
# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

# Required URL patterns (regex, case-insensitive)
REQUIRED_PATTERNS = {
    'wikipedia': r'.*wikipedia\.org.*',
    'github': r'.*github\.com.*',
    'stackoverflow': r'.*stackoverflow\.com.*',
    'mdn': r'.*developer\.mozilla\.org.*'
}


def verify_task(traj, env_info, task_info):
    """
    Main verification function for multi_tab_session@1 task.
    
    Args:
        traj: Trajectory data (unused for this task)
        env_info: Environment information including copy_from_env function
        task_info: Task-specific information
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    try:
        # Get all tabs from CDP
        tabs = get_all_tabs(copy_from_env)
        
        if tabs is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve tab information from Chrome CDP"
            }
        
        # Verify tabs
        result = verify_multi_tab_session(tabs)
        
        # Calculate score (25 points per correct tab)
        tabs_found = result['tabs_found']
        total_required = result['required_tabs']
        total_tabs = result['total_tabs']
        
        score = (tabs_found / total_required) * 100
        
        # Pass threshold: at least 3 out of 4 tabs correct, and not too many extra tabs
        passed = tabs_found >= 3 and total_tabs <= 5
        
        # Generate detailed feedback
        feedback_parts = [
            f"Found {tabs_found}/{total_required} required tabs",
            f"Total tabs open: {total_tabs}"
        ]
        
        for name, found in result['details'].items():
            status = "✓" if found else "✗"
            feedback_parts.append(f"{status} {name.upper()}: {'Found' if found else 'Missing'}")
        
        if total_tabs > total_required + 1:
            feedback_parts.append(f"⚠ Too many tabs open ({total_tabs - total_required} extra)")
        
        if tabs_found < total_required:
            missing = [name for name, found in result['details'].items() if not found]
            feedback_parts.append(f"Missing: {', '.join(missing)}")
        
        feedback = "\n".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_all_tabs(copy_from_env) -> List[Dict[str, Any]]:
    """
    Get all open tabs from Chrome via CDP.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        List of tab dictionaries with 'url', 'title', etc., or None on failure
    """
    try:
        # Create temporary file for tabs JSON
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        # Copy tabs JSON from container
        success, error = copy_from_env("/tmp/all_tabs.json", temp_path)
        
        if not success:
            logger.error(f"Failed to copy tabs JSON: {error}")
            return None
        
        # Read and parse tabs JSON
        with open(temp_path, 'r') as f:
            tabs = json.load(f)
        
        # Clean up temp file
        os.unlink(temp_path)
        
        if not isinstance(tabs, list):
            logger.error(f"Tabs data is not a list: {type(tabs)}")
            return None
        
        logger.info(f"Successfully retrieved {len(tabs)} tabs from CDP")
        for i, tab in enumerate(tabs):
            logger.info(f"  Tab {i+1}: {tab.get('url', 'NO URL')}")
        
        return tabs
        
    except Exception as e:
        logger.error(f"Error getting tabs: {e}", exc_info=True)
        return None


def verify_url_pattern(url: str, pattern: str) -> bool:
    """
    Check if URL matches expected regex pattern (case insensitive).
    
    Args:
        url: URL string to check
        pattern: Regex pattern to match
        
    Returns:
        True if URL matches pattern, False otherwise
    """
    return bool(re.search(pattern, url, re.IGNORECASE))


def verify_multi_tab_session(tabs: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify that all required tabs are present.
    
    Args:
        tabs: List of tab dictionaries from CDP
        
    Returns:
        Dictionary with verification results
    """
    # Extract URLs from tabs
    tab_urls = [tab.get('url', '') for tab in tabs]
    
    # Check which required patterns are found
    found = {name: False for name in REQUIRED_PATTERNS.keys()}
    
    for name, pattern in REQUIRED_PATTERNS.items():
        for url in tab_urls:
            if verify_url_pattern(url, pattern):
                found[name] = True
                logger.info(f"✓ Found {name}: {url}")
                break
        
        if not found[name]:
            logger.warning(f"✗ Missing {name} (pattern: {pattern})")
    
    tabs_found = sum(found.values())
    total_tabs = len(tab_urls)
    required_tabs = len(REQUIRED_PATTERNS)
    
    return {
        'tabs_found': tabs_found,
        'total_tabs': total_tabs,
        'required_tabs': required_tabs,
        'details': found,
        'passed': tabs_found >= 3 and total_tabs <= 5
    }


def check_for_duplicate_tabs(tabs: List[Dict[str, Any]]) -> List[str]:
    """
    Check if any URL patterns appear multiple times.
    
    Args:
        tabs: List of tab dictionaries from CDP
        
    Returns:
        List of pattern names that appear more than once
    """
    duplicates = []
    tab_urls = [tab.get('url', '') for tab in tabs]
    
    for name, pattern in REQUIRED_PATTERNS.items():
        count = sum(1 for url in tab_urls if verify_url_pattern(url, pattern))
        if count > 1:
            duplicates.append(name)
            logger.warning(f"⚠ Duplicate tabs for {name}: found {count} times")
    
    return duplicates
