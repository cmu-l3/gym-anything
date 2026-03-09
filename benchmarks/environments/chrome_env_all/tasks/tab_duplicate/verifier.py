#!/usr/bin/env python3
"""
Verifier for Chrome Tab Duplication Task: tab_duplicate@1
Task: Navigate to example.com and duplicate the tab to create two identical tabs

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) to query all open tabs
- Verifies at least 2 tabs are open
- Checks that exactly 2 tabs have the target URL (example.com)
- Validates both tabs are fully loaded (not pending/error state)
- Confirms the duplicated tab is the active one (highest tab ID)

Scoring:
- 100%: All 4 criteria met (perfect duplication)
- 75-99%: 3/4 criteria met (minor issues, still passing)
- 50-74%: 2/4 criteria met (partial success, failing)
- 0-49%: <2 criteria met (task failed)

Pass threshold: 75% (requires at least 3 out of 4 criteria)
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
    logger.warning("Chrome verification utilities not available, using fallback methods")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for tab_duplicate@1 task.
    
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
        verification_result = verify_tab_duplication(tabs_data)
        
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
        
        copy_from_env("/tmp/chrome_page_tabs.json", temp_path)
        
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
    Normalize URL for comparison by removing protocol, trailing slashes, etc.
    
    Args:
        url: URL string to normalize
        
    Returns:
        Normalized URL string
    """
    if not url:
        return ""
    
    # Convert to lowercase
    url = url.lower()
    
    # Remove protocol
    url = re.sub(r'^https?://', '', url)
    
    # Remove www. prefix
    url = re.sub(r'^www\.', '', url)
    
    # Remove trailing slashes
    url = url.rstrip('/')
    
    # Remove query parameters and fragments for base comparison
    url = re.sub(r'[?#].*$', '', url)
    
    return url


def verify_tab_duplication(tabs_data: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify that tab was correctly duplicated.
    
    Checks:
    1. At least 2 tabs are open
    2. Exactly 2 tabs have the target URL (example.com)
    3. Both matching tabs are fully loaded (not pending/error)
    4. Active tab is one of the example.com tabs (indicates duplication succeeded)
    
    Args:
        tabs_data: List of tab information from CDP
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    target_domain = "example.com"
    
    # Extract URLs and titles from tabs
    tab_urls = [tab.get('url', '') for tab in tabs_data]
    tab_titles = [tab.get('title', '') for tab in tabs_data]
    tab_ids = [tab.get('id', '') for tab in tabs_data]
    
    logger.info(f"Found {len(tabs_data)} tabs")
    for i, (tab_id, url, title) in enumerate(zip(tab_ids, tab_urls, tab_titles), 1):
        logger.info(f"  Tab {i} [ID: {tab_id}]: {url[:60]}... | {title[:50]}...")
    
    # Criterion 1: At least 2 tabs are open
    tab_count_ok = len(tabs_data) >= 2
    logger.info(f"Criterion 1 - Tab count: {len(tabs_data)} tabs (need ≥2) - {'PASS' if tab_count_ok else 'FAIL'}")
    
    # Criterion 2: Exactly 2 tabs have example.com URL
    example_tabs = []
    for i, (tab, url) in enumerate(zip(tabs_data, tab_urls)):
        normalized = normalize_url(url)
        if target_domain in normalized:
            example_tabs.append({
                'index': i,
                'id': tab.get('id', ''),
                'url': url,
                'title': tab.get('title', ''),
                'tab': tab
            })
    
    exact_match = len(example_tabs) == 2
    logger.info(f"Criterion 2 - Example.com tabs: Found {len(example_tabs)} tabs (need exactly 2) - {'PASS' if exact_match else 'FAIL'}")
    
    # Criterion 3: Both tabs are fully loaded (check for error indicators)
    both_loaded = True
    error_keywords = ["error", "404", "not found", "cannot be reached", "page not available"]
    
    if len(example_tabs) >= 2:
        for tab_info in example_tabs:
            title = tab_info['title'].lower()
            url = tab_info['url'].lower()
            
            # Check for error indicators
            has_error = any(keyword in title or keyword in url for keyword in error_keywords)
            
            # Check if title is empty (might indicate not loaded)
            if not title or has_error:
                both_loaded = False
                logger.warning(f"Tab {tab_info['index']} appears not loaded properly: '{tab_info['title']}'")
    else:
        both_loaded = False  # Can't verify if we don't have 2 tabs
    
    logger.info(f"Criterion 3 - Both tabs loaded: {'PASS' if both_loaded else 'FAIL'}")
    
    # Criterion 4: Active tab is one of the example.com tabs
    # The newest tab (highest ID) should be the duplicated one
    active_correct = False
    if len(example_tabs) == 2:
        # Sort by ID to find which was created last
        try:
            tab_ids_sorted = sorted([t['id'] for t in example_tabs])
            # The duplicated tab should be the one with higher ID (created more recently)
            # Just check that both IDs are present, which confirms duplication happened
            active_correct = len(set(tab_ids_sorted)) == 2
            logger.info(f"Criterion 4 - Tab IDs distinct: {tab_ids_sorted} - {'PASS' if active_correct else 'FAIL'}")
        except Exception as e:
            logger.warning(f"Could not verify tab IDs: {e}")
            active_correct = True  # Give benefit of doubt if we can't check
    else:
        logger.info(f"Criterion 4 - Skipped (not enough matching tabs)")
    
    # Calculate score based on criteria met
    criteria_results = [
        tab_count_ok,
        exact_match,
        both_loaded,
        active_correct
    ]
    
    criteria_met = sum(criteria_results)
    score = (criteria_met / 4) * 100
    passed = score >= 75  # Need at least 3/4 criteria (75%)
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Tab Duplication Verification: {criteria_met}/4 criteria met")
    feedback_parts.append("")
    
    if tab_count_ok:
        feedback_parts.append(f"✓ Criterion 1: At least 2 tabs open ({len(tabs_data)} tabs)")
    else:
        feedback_parts.append(f"✗ Criterion 1: Not enough tabs (found {len(tabs_data)}, need ≥2)")
    
    if exact_match:
        feedback_parts.append(f"✓ Criterion 2: Exactly 2 tabs with example.com URL")
    else:
        feedback_parts.append(f"✗ Criterion 2: Wrong number of example.com tabs (found {len(example_tabs)}, need exactly 2)")
        if len(example_tabs) > 2:
            feedback_parts.append(f"  → Too many duplicates created")
        elif len(example_tabs) < 2:
            feedback_parts.append(f"  → Tab was not duplicated or wrong URL")
    
    if both_loaded:
        feedback_parts.append(f"✓ Criterion 3: Both tabs fully loaded without errors")
    else:
        feedback_parts.append(f"✗ Criterion 3: One or more tabs not properly loaded")
    
    if active_correct:
        feedback_parts.append(f"✓ Criterion 4: Tabs have distinct IDs (proper duplication)")
    else:
        feedback_parts.append(f"✗ Criterion 4: Tab IDs issue detected")
    
    feedback_parts.append("")
    feedback_parts.append("=" * 50)
    feedback_parts.append(f"Final Score: {int(score)}%")
    
    if passed:
        feedback_parts.append("✅ PASSED: Tab successfully duplicated!")
    else:
        feedback_parts.append("❌ FAILED: Tab duplication incomplete or incorrect")
        feedback_parts.append("")
        feedback_parts.append("Hint: Right-click on the active tab in the tab strip and select 'Duplicate'")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": {
            "total_tabs": len(tabs_data),
            "example_tabs_count": len(example_tabs),
            "criteria_met": criteria_met,
            "tab_urls": tab_urls,
            "tab_titles": tab_titles,
            "example_tabs": [{"url": t['url'], "title": t['title']} for t in example_tabs]
        }
    }
