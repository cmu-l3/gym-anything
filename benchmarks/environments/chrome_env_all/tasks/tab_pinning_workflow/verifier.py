#!/usr/bin/env python3
"""
Verifier for Chrome Tab Pinning Workflow Task: tab_pinning_workflow@1
Task: Pin Gmail and Calendar tabs to keep them persistent and accessible

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) to query tab positions
- Pinned tabs always appear in the first positions in Chrome's tab list
- Verifies that Gmail and Calendar tabs are in positions 0 and 1
- Ensures all 4 original tabs still exist
- Confirms no duplicate tabs were created
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for tab_pinning_workflow@1 task.
    
    Verifies:
    1. Exactly 2 tabs are in "pinned" positions (first 2 positions)
    2. Those 2 tabs are Gmail and Calendar
    3. All 4 original tabs still exist
    4. Tab ordering shows Gmail and Calendar first
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment information with copy_from_env function
        task_info: Task configuration
        
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
        verification_result = verify_tab_pinning(tabs_data)
        
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
        copy_from_env: Function to copy files from container
        
    Returns:
        List of tab dictionaries or None if failed
    """
    try:
        # Copy the CDP JSON data
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try primary location
        try:
            copy_from_env("/tmp/chrome_page_tabs.json", temp_path)
        except Exception as e:
            logger.warning(f"Primary location failed: {e}, trying backup")
            copy_from_env("/tmp/tab_pinning_verification/chrome_page_tabs.json", temp_path)
        
        with open(temp_path, 'r') as f:
            tabs_data = json.load(f)
        
        os.unlink(temp_path)
        
        logger.info(f"Successfully retrieved {len(tabs_data)} tab(s) from CDP")
        return tabs_data
        
    except Exception as e:
        logger.error(f"Failed to get tabs data: {e}")
        return None


def normalize_url(url: str) -> str:
    """Normalize URL for comparison."""
    if not url:
        return ""
    url = url.lower().strip()
    url = url.rstrip('/')
    url = url.replace('http://', '').replace('https://', '')
    return url


def identify_tab_type(url: str, title: str) -> str:
    """
    Identify what type of tab this is based on URL and title.
    
    Returns:
        One of: 'gmail', 'calendar', 'wikipedia', 'hackernews', 'other'
    """
    url_lower = url.lower()
    title_lower = title.lower()
    
    if 'mail.google.com' in url_lower:
        return 'gmail'
    elif 'calendar.google.com' in url_lower:
        return 'calendar'
    elif 'wikipedia.org/wiki/chrome' in url_lower:
        return 'wikipedia'
    elif 'news.ycombinator.com' in url_lower:
        return 'hackernews'
    else:
        return 'other'


def verify_tab_pinning(tabs_data: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify that Gmail and Calendar tabs are pinned (in first 2 positions).
    
    Chrome's behavior with pinned tabs:
    - Pinned tabs always appear first in the tab list
    - They maintain their position at the leftmost side
    - CDP returns tabs in the order they appear in the browser
    
    Verification criteria:
    1. Exactly 2 tabs pinned (Gmail and Calendar in positions 0 and 1)
    2. Correct tab targets (Gmail and Calendar specifically)
    3. Proper positioning (in first two positions)
    4. All tabs preserved (all 4 original tabs still exist)
    
    Args:
        tabs_data: List of tab information from CDP
        
    Returns:
        Verification result dict
    """
    # Extract tab information
    tab_urls = [tab.get('url', '') for tab in tabs_data]
    tab_titles = [tab.get('title', '') for tab in tabs_data]
    
    logger.info(f"Analyzing {len(tabs_data)} tabs")
    for i, (url, title) in enumerate(zip(tab_urls, tab_titles), 0):
        tab_type = identify_tab_type(url, title)
        logger.info(f"  Position {i}: {tab_type} | {url[:50]}... | {title[:40]}...")
    
    # Identify all tabs by type
    tab_types = [identify_tab_type(url, title) for url, title in zip(tab_urls, tab_titles)]
    
    # Count occurrences of each tab type
    tab_counts = {
        'gmail': tab_types.count('gmail'),
        'calendar': tab_types.count('calendar'),
        'wikipedia': tab_types.count('wikipedia'),
        'hackernews': tab_types.count('hackernews'),
        'other': tab_types.count('other')
    }
    
    # Criterion 1: All 4 tabs preserved
    total_expected_tabs = 4
    all_tabs_preserved = len(tabs_data) == total_expected_tabs
    
    # Check that all expected tab types are present
    required_tabs = ['gmail', 'calendar', 'wikipedia', 'hackernews']
    all_types_present = all(tab_counts.get(tab_type, 0) >= 1 for tab_type in required_tabs)
    
    logger.info(f"✓ Tab preservation check: {len(tabs_data)} tabs total, all types present: {all_types_present}")
    
    # Criterion 2: Gmail and Calendar are in first 2 positions
    first_two_types = tab_types[:2] if len(tab_types) >= 2 else []
    
    gmail_in_first_two = 'gmail' in first_two_types
    calendar_in_first_two = 'calendar' in first_two_types
    both_in_first_two = gmail_in_first_two and calendar_in_first_two
    
    logger.info(f"✓ Position check: First two tabs are {first_two_types}")
    logger.info(f"  Gmail in first 2: {gmail_in_first_two}")
    logger.info(f"  Calendar in first 2: {calendar_in_first_two}")
    
    # Criterion 3: Correct targets (exactly Gmail and Calendar pinned)
    first_two_are_productivity = set(first_two_types) == {'gmail', 'calendar'}
    
    logger.info(f"✓ Target check: First two tabs are productivity apps: {first_two_are_productivity}")
    
    # Criterion 4: No duplicates
    no_duplicates = all(count <= 1 for tab_type, count in tab_counts.items() if tab_type != 'other')
    
    logger.info(f"✓ Duplicate check: No duplicates detected: {no_duplicates}")
    
    # Additional criterion: Gmail should ideally be position 0, Calendar position 1
    # (though either order is acceptable)
    ideal_order = False
    if len(tab_types) >= 2:
        if (tab_types[0] == 'gmail' and tab_types[1] == 'calendar') or \
           (tab_types[0] == 'calendar' and tab_types[1] == 'gmail'):
            ideal_order = True
    
    logger.info(f"✓ Order check: Ideal ordering: {ideal_order}")
    
    # Calculate score based on criteria
    criteria_results = [
        all_tabs_preserved and all_types_present,  # All 4 tabs exist
        both_in_first_two,                          # Gmail and Calendar in first 2 positions
        first_two_are_productivity,                 # ONLY Gmail and Calendar in first 2
        no_duplicates                               # No duplicate tabs
    ]
    
    criteria_met = sum(criteria_results)
    
    # Bonus points for ideal order
    if ideal_order and criteria_met == 4:
        score = 100
    else:
        score = int((criteria_met / 4) * 100)
    
    passed = score >= 75  # Need at least 3/4 criteria
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Tab Pinning Verification: {criteria_met}/4 criteria met")
    
    if all_tabs_preserved and all_types_present:
        feedback_parts.append(f"✓ All 4 tabs preserved: Gmail, Calendar, Wikipedia, Hacker News")
    else:
        missing = [t for t in required_tabs if tab_counts.get(t, 0) == 0]
        feedback_parts.append(f"✗ Tab preservation issue: {len(tabs_data)} tabs found, missing: {missing if missing else 'none'}")
    
    if both_in_first_two:
        feedback_parts.append(f"✓ Gmail and Calendar in first 2 positions (pinned)")
    else:
        feedback_parts.append(f"✗ Gmail/Calendar not in first 2 positions: positions are {first_two_types}")
    
    if first_two_are_productivity:
        feedback_parts.append(f"✓ First 2 positions contain exactly Gmail and Calendar")
    else:
        feedback_parts.append(f"✗ First 2 positions incorrect: {first_two_types} (should be gmail, calendar)")
    
    if no_duplicates:
        feedback_parts.append(f"✓ No duplicate tabs detected")
    else:
        duplicates = [f"{t}({c})" for t, c in tab_counts.items() if c > 1 and t != 'other']
        feedback_parts.append(f"✗ Duplicate tabs found: {duplicates}")
    
    feedback_parts.append("")
    feedback_parts.append(f"Tab order: {' → '.join(tab_types)}")
    
    if passed:
        feedback_parts.append("✅ Task completed successfully - Gmail and Calendar tabs are pinned!")
    else:
        feedback_parts.append("❌ Task incomplete - tabs not properly pinned")
        feedback_parts.append("Hint: Right-click on Gmail tab → 'Pin tab', then same for Calendar")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "total_tabs": len(tabs_data),
            "criteria_met": criteria_met,
            "tab_types": tab_types,
            "first_two_positions": first_two_types,
            "tab_counts": tab_counts,
            "tab_urls": tab_urls,
            "tab_titles": tab_titles
        }
    }
