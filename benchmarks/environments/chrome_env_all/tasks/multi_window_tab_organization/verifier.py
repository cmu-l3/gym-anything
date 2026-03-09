#!/usr/bin/env python3
"""
Verifier for Chrome Multi-Window Tab Organization Task (multi_window_tab_organization@1)

Task: Organize 5 tabs across 2 Chrome windows with specific distribution:
  - Window 1: GitHub, Stack Overflow (2 tabs)
  - Window 2: MDN, Node.js, Python docs (3 tabs)

Verification Strategy:
  1. Use wmctrl data to verify exactly 2 Chrome windows exist
  2. Use CDP data to verify exactly 5 page tabs exist
  3. Verify all 5 expected URLs are present
  4. Verify correct URL grouping (dev tools vs documentation)
  5. Ensure no duplicate URLs or error pages

Scoring:
  - 100%: All 5 criteria met (perfect organization)
  - 80-99%: 4/5 criteria met (minor issue)
  - 60-79%: 3/5 criteria met (partial success)
  - <60%: <3 criteria met (insufficient)
  
Pass threshold: 75% (need 4 out of 5 criteria)
"""

import logging
import sys
import os
import json
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
    logger.warning("Chrome verification utilities not available, using fallback")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for multi_window_tab_organization@1.
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment info with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Extract data from container
        window_count = get_window_count(copy_from_env)
        tabs_data = get_tabs_data(copy_from_env)
        
        if tabs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve tab information from Chrome CDP"
            }
        
        # Perform verification
        result = verify_multi_window_organization(window_count, tabs_data)
        
        # Cleanup
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


def get_window_count(copy_from_env) -> int:
    """
    Get the number of Chrome windows from exported data.
    
    Returns:
        Integer count of Chrome windows
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        copy_from_env("/tmp/chrome_window_count.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            count = int(f.read().strip())
        
        os.unlink(temp_file.name)
        
        logger.info(f"Retrieved window count: {count}")
        return count
        
    except Exception as e:
        logger.error(f"Failed to get window count: {e}")
        return 0


def get_tabs_data(copy_from_env) -> Optional[List[Dict[str, Any]]]:
    """
    Retrieve tab information from container using CDP data.
    
    Returns:
        List of tab dictionaries or None on failure
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        copy_from_env("/tmp/chrome_page_tabs.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            tabs_data = json.load(f)
        
        os.unlink(temp_file.name)
        
        logger.info(f"Successfully retrieved {len(tabs_data)} tab(s) from CDP")
        return tabs_data
        
    except Exception as e:
        logger.error(f"Failed to get tabs data: {e}")
        return None


def normalize_url(url: str) -> str:
    """Normalize URL for comparison."""
    if not url:
        return ""
    url = url.lower().rstrip('/')
    # Remove protocol
    for proto in ['https://', 'http://']:
        if url.startswith(proto):
            url = url[len(proto):]
    # Remove www.
    if url.startswith('www.'):
        url = url[4:]
    return url


def verify_multi_window_organization(window_count: int, tabs_data: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify multi-window tab organization meets requirements.
    
    Checks:
    1. Exactly 2 Chrome windows exist
    2. Exactly 5 page tabs exist
    3. All expected URLs present (github, stackoverflow, mdn, nodejs, python)
    4. Correct URL categorization (dev: 2, docs: 3)
    5. No duplicates or error pages
    
    Args:
        window_count: Number of Chrome windows
        tabs_data: List of tab information from CDP
        
    Returns:
        Verification result dict
    """
    # Expected URLs organized by category
    dev_urls = {
        "github": ["github.com", "www.github.com"],
        "stackoverflow": ["stackoverflow.com", "www.stackoverflow.com"]
    }
    
    doc_urls = {
        "mdn": ["developer.mozilla.org"],
        "nodejs": ["nodejs.org", "www.nodejs.org"],
        "python": ["python.org", "www.python.org", "docs.python.org"]
    }
    
    all_expected = {**dev_urls, **doc_urls}
    
    # Extract URLs and titles
    tab_urls = [tab.get('url', '') for tab in tabs_data]
    tab_titles = [tab.get('title', '') for tab in tabs_data]
    
    logger.info(f"Window count: {window_count}")
    logger.info(f"Tab count: {len(tabs_data)}")
    for i, (url, title) in enumerate(zip(tab_urls, tab_titles), 1):
        logger.info(f"  Tab {i}: {url[:60]}... | {title[:40]}...")
    
    # Criterion 1: Exactly 2 windows
    criterion_1 = window_count == 2
    logger.info(f"✓ Criterion 1 (Window count = 2): {'PASS' if criterion_1 else 'FAIL'} (found {window_count})")
    
    # Criterion 2: Exactly 5 tabs
    criterion_2 = len(tabs_data) == 5
    logger.info(f"✓ Criterion 2 (Tab count = 5): {'PASS' if criterion_2 else 'FAIL'} (found {len(tabs_data)})")
    
    # Criterion 3: All expected URLs present
    urls_found = {key: False for key in all_expected.keys()}
    url_matches = {key: [] for key in all_expected.keys()}
    
    for tab_url in tab_urls:
        normalized = normalize_url(tab_url)
        for key, patterns in all_expected.items():
            if any(pattern in normalized for pattern in patterns):
                urls_found[key] = True
                url_matches[key].append(tab_url)
                break
    
    all_urls_present = all(urls_found.values())
    missing_urls = [k for k, v in urls_found.items() if not v]
    
    logger.info(f"✓ Criterion 3 (All URLs present): {'PASS' if all_urls_present else 'FAIL'}")
    for key, found in urls_found.items():
        logger.info(f"    {key}: {'✓' if found else '✗'}")
    
    # Criterion 4: Correct URL categorization
    dev_count = sum(1 for k in dev_urls.keys() if urls_found.get(k, False))
    doc_count = sum(1 for k in doc_urls.keys() if urls_found.get(k, False))
    
    correct_distribution = (dev_count == 2 and doc_count == 3)
    logger.info(f"✓ Criterion 4 (Distribution): {'PASS' if correct_distribution else 'FAIL'} (dev: {dev_count}/2, docs: {doc_count}/3)")
    
    # Criterion 5: No duplicates or error pages
    has_duplicates = False
    for key, matches in url_matches.items():
        if len(matches) > 1:
            has_duplicates = True
            logger.warning(f"  Duplicate detected for {key}: {len(matches)} instances")
    
    error_keywords = ["error", "404", "not found", "cannot be reached", "problem loading"]
    has_errors = any(
        any(keyword in title.lower() for keyword in error_keywords)
        for title in tab_titles
    )
    
    no_issues = not has_duplicates and not has_errors
    logger.info(f"✓ Criterion 5 (No duplicates/errors): {'PASS' if no_issues else 'FAIL'}")
    if has_duplicates:
        logger.info(f"    Duplicates detected")
    if has_errors:
        logger.info(f"    Error pages detected")
    
    # Calculate score
    criteria = [
        criterion_1,
        criterion_2,
        all_urls_present,
        correct_distribution,
        no_issues
    ]
    
    criteria_met = sum(criteria)
    score = int((criteria_met / 5) * 100)
    passed = score >= 75  # Need 4 out of 5 criteria
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Multi-Window Organization Verification: {criteria_met}/5 criteria met")
    feedback_parts.append("")
    feedback_parts.append(f"{'✓' if criterion_1 else '✗'} Criterion 1: Window count = 2 (found {window_count})")
    feedback_parts.append(f"{'✓' if criterion_2 else '✗'} Criterion 2: Tab count = 5 (found {len(tabs_data)})")
    feedback_parts.append(f"{'✓' if all_urls_present else '✗'} Criterion 3: All URLs present")
    
    if not all_urls_present:
        feedback_parts.append(f"    Missing: {', '.join(missing_urls)}")
    
    feedback_parts.append(f"{'✓' if correct_distribution else '✗'} Criterion 4: Correct distribution (dev: {dev_count}/2, docs: {doc_count}/3)")
    feedback_parts.append(f"{'✓' if no_issues else '✗'} Criterion 5: No duplicates or errors")
    
    if has_duplicates:
        feedback_parts.append("    ⚠ Duplicate URLs detected")
    if has_errors:
        feedback_parts.append("    ⚠ Error pages detected")
    
    feedback_parts.append("")
    if passed:
        feedback_parts.append("✅ Task completed successfully! Tabs properly organized across 2 windows.")
    else:
        feedback_parts.append("❌ Task incomplete - review the criteria above.")
        if window_count != 2:
            feedback_parts.append(f"   Hint: Create exactly 2 Chrome windows (found {window_count})")
        if len(tabs_data) != 5:
            feedback_parts.append(f"   Hint: Open exactly 5 tabs total (found {len(tabs_data)})")
        if not all_urls_present:
            feedback_parts.append(f"   Hint: Missing URLs - {', '.join(missing_urls)}")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "window_count": window_count,
            "tab_count": len(tabs_data),
            "criteria_met": criteria_met,
            "urls_found": urls_found,
            "dev_count": dev_count,
            "doc_count": doc_count,
            "has_duplicates": has_duplicates,
            "has_errors": has_errors,
            "tab_urls": tab_urls
        }
    }
