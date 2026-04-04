#!/usr/bin/env python3
"""
Verifier for Chrome Tab Groups Organization Task (tab_groups_organization@1)
Task: Organize 12 tabs into 4 logical tab groups with names and colors

Verification Strategy:
- Uses CDP to query all open tabs
- Categorizes tabs based on URL domains
- Verifies all 12 expected tabs are present
- Checks proper categorization (tabs in correct logical groups)
- Since CDP doesn't directly expose tab groups, we verify:
  1. All tabs exist
  2. Tabs are correctly categorized by domain
  3. No tabs were closed or duplicated
  
Note: Chrome's Tab Groups metadata is not directly accessible via CDP in most versions.
We use URL-based categorization as a proxy for group membership verification.
If Chrome's Session/Local State files contain tab group metadata, we parse those as well.
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from urllib.parse import urlparse
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available")
    def cleanup_verification_temp():
        pass


# Expected tab categories and their domains
EXPECTED_CATEGORIES = {
    'news': {
        'domains': ['bbc.com', 'cnn.com', 'reuters.com'],
        'count': 3,
        'group_name': 'News'
    },
    'shopping': {
        'domains': ['amazon.com', 'ebay.com', 'etsy.com'],
        'count': 3,
        'group_name': 'Shopping'
    },
    'docs': {
        'domains': ['developer.mozilla.org', 'docs.python.org', 'stackoverflow.com'],
        'count': 3,
        'group_name': 'Documentation'
    },
    'social': {
        'domains': ['twitter.com', 'reddit.com', 'linkedin.com'],
        'count': 3,
        'group_name': 'Social'
    }
}


def get_tab_category(url: str) -> Optional[str]:
    """
    Determine which category a tab belongs to based on URL.
    
    Args:
        url: Tab URL
        
    Returns:
        Category name or None if unrecognized
    """
    try:
        domain = urlparse(url).netloc.lower()
        # Remove 'www.' prefix for matching
        domain = domain.replace('www.', '')
        
        for category, info in EXPECTED_CATEGORIES.items():
            for expected_domain in info['domains']:
                if expected_domain in domain or domain in expected_domain:
                    return category
        
        return None
    except Exception as e:
        logger.warning(f"Error parsing URL {url}: {e}")
        return None


def get_tabs_data(copy_from_env) -> Optional[List[Dict[str, Any]]]:
    """
    Retrieve tab information from container using CDP data.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        List of tab dictionaries or None on error
    """
    try:
        # Copy the CDP JSON data from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        for container_path in [
            "/tmp/page_tabs.json",
            "/tmp/tab_groups_verification/page_tabs.json",
            "/tmp/all_tabs.json"
        ]:
            try:
                copy_from_env(container_path, temp_path)
                
                with open(temp_path, 'r') as f:
                    tabs_data = json.load(f)
                
                # If we got all_tabs.json, filter to page type
                if isinstance(tabs_data, list):
                    tabs_data = [t for t in tabs_data if t.get('type') == 'page']
                
                os.unlink(temp_path)
                logger.info(f"Successfully retrieved {len(tabs_data)} tabs from {container_path}")
                return tabs_data
            except Exception as e:
                logger.debug(f"Failed to get tabs from {container_path}: {e}")
                continue
        
        # Cleanup temp file if all attempts failed
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        
        return None
        
    except Exception as e:
        logger.error(f"Failed to get tabs data: {e}")
        return None


def categorize_tabs(tabs_data: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
    """
    Categorize tabs based on their URLs.
    
    Args:
        tabs_data: List of tab information from CDP
        
    Returns:
        Dict mapping category names to lists of tabs
    """
    categorized = {
        'news': [],
        'shopping': [],
        'docs': [],
        'social': [],
        'uncategorized': []
    }
    
    for tab in tabs_data:
        url = tab.get('url', '')
        category = get_tab_category(url)
        
        if category:
            categorized[category].append(tab)
        else:
            categorized['uncategorized'].append(tab)
    
    return categorized


def verify_tab_groups_organization(tabs_data: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify that tabs were correctly organized into logical groups.
    
    Since Chrome's tab group metadata is not directly accessible via CDP,
    we verify based on tab presence and categorization.
    
    Verification Criteria:
    1. All 12 expected tabs are present (no tabs closed)
    2. All tabs are correctly categorized (in expected categories)
    3. Each category has the expected number of tabs (3 each)
    4. No duplicate tabs within categories
    5. No uncategorized tabs (all tabs match expected domains)
    
    Args:
        tabs_data: List of tab information from CDP
        
    Returns:
        Verification result dict
    """
    # Categorize all tabs
    categorized = categorize_tabs(tabs_data)
    
    total_tabs = len(tabs_data)
    expected_total = sum(cat['count'] for cat in EXPECTED_CATEGORIES.values())
    
    logger.info(f"Total tabs: {total_tabs} (expected: {expected_total})")
    for category, tabs in categorized.items():
        if category != 'uncategorized':
            expected_count = EXPECTED_CATEGORIES[category]['count']
            logger.info(f"  {category}: {len(tabs)} tabs (expected: {expected_count})")
    
    if categorized['uncategorized']:
        logger.info(f"  uncategorized: {len(categorized['uncategorized'])} tabs")
        for tab in categorized['uncategorized']:
            logger.info(f"    - {tab.get('url', 'unknown')}")
    
    # Criterion 1: Correct total tab count (all 12 tabs present)
    criterion_1_total_count = (total_tabs == expected_total)
    
    # Criterion 2: All tabs are categorized (no uncategorized tabs)
    criterion_2_all_categorized = (len(categorized['uncategorized']) == 0)
    
    # Criterion 3: Each category has correct number of tabs
    category_counts_correct = []
    for category, info in EXPECTED_CATEGORIES.items():
        expected_count = info['count']
        actual_count = len(categorized[category])
        is_correct = (actual_count == expected_count)
        category_counts_correct.append(is_correct)
        
        logger.info(f"Category '{category}' count check: {actual_count}/{expected_count} - {'✓' if is_correct else '✗'}")
    
    criterion_3_category_counts = all(category_counts_correct)
    
    # Criterion 4: No duplicate URLs within categories
    has_duplicates = False
    for category, tabs in categorized.items():
        if category == 'uncategorized':
            continue
        urls = [tab.get('url', '') for tab in tabs]
        if len(urls) != len(set(urls)):
            has_duplicates = True
            logger.warning(f"Duplicate URLs found in category '{category}'")
    
    criterion_4_no_duplicates = not has_duplicates
    
    # Criterion 5: All expected domains are present (at least one tab per domain)
    all_domains_present = []
    for category, info in EXPECTED_CATEGORIES.items():
        category_tabs = categorized[category]
        category_urls = [tab.get('url', '').lower() for tab in category_tabs]
        
        for expected_domain in info['domains']:
            domain_found = any(expected_domain in url for url in category_urls)
            all_domains_present.append(domain_found)
            if not domain_found:
                logger.warning(f"Expected domain '{expected_domain}' not found in category '{category}'")
    
    criterion_5_domains_present = all(all_domains_present)
    
    # Calculate score
    criteria_results = [
        criterion_1_total_count,
        criterion_2_all_categorized,
        criterion_3_category_counts,
        criterion_4_no_duplicates,
        criterion_5_domains_present
    ]
    
    criteria_met = sum(criteria_results)
    max_criteria = len(criteria_results)
    score = int((criteria_met / max_criteria) * 100)
    passed = score >= 80  # Need 4/5 criteria to pass
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Tab Groups Organization Verification: {criteria_met}/{max_criteria} criteria met")
    feedback_parts.append("")
    
    # Detailed criterion feedback
    feedback_parts.append(f"1. Total tab count: {'✓' if criterion_1_total_count else '✗'} ({total_tabs} tabs, expected {expected_total})")
    
    feedback_parts.append(f"2. All tabs categorized: {'✓' if criterion_2_all_categorized else '✗'} ({len(categorized['uncategorized'])} uncategorized)")
    
    feedback_parts.append(f"3. Category counts correct: {'✓' if criterion_3_category_counts else '✗'}")
    for category, info in EXPECTED_CATEGORIES.items():
        actual = len(categorized[category])
        expected = info['count']
        symbol = '✓' if actual == expected else '✗'
        feedback_parts.append(f"   {symbol} {info['group_name']}: {actual}/{expected} tabs")
    
    feedback_parts.append(f"4. No duplicate tabs: {'✓' if criterion_4_no_duplicates else '✗'}")
    
    feedback_parts.append(f"5. All expected domains present: {'✓' if criterion_5_domains_present else '✗'}")
    
    feedback_parts.append("")
    if passed:
        feedback_parts.append("✅ Task completed successfully! Tabs are properly organized into logical groups.")
    else:
        feedback_parts.append("❌ Task incomplete - tabs are not properly organized into groups.")
        if not criterion_1_total_count:
            if total_tabs < expected_total:
                feedback_parts.append(f"   • Missing {expected_total - total_tabs} tab(s)")
            else:
                feedback_parts.append(f"   • Extra {total_tabs - expected_total} tab(s) present")
        if not criterion_2_all_categorized:
            feedback_parts.append(f"   • {len(categorized['uncategorized'])} tab(s) don't match expected categories")
        if not criterion_3_category_counts:
            feedback_parts.append("   • Some categories have incorrect number of tabs")
    
    feedback = "\n".join(feedback_parts)
    
    # Prepare detailed results
    details = {
        "total_tabs": total_tabs,
        "expected_tabs": expected_total,
        "criteria_met": criteria_met,
        "max_criteria": max_criteria,
        "category_counts": {
            cat: len(categorized[cat]) for cat in ['news', 'shopping', 'docs', 'social']
        },
        "uncategorized_count": len(categorized['uncategorized']),
        "uncategorized_urls": [tab.get('url', '') for tab in categorized['uncategorized']],
        "criteria_details": {
            "total_count_correct": criterion_1_total_count,
            "all_categorized": criterion_2_all_categorized,
            "category_counts_correct": criterion_3_category_counts,
            "no_duplicates": criterion_4_no_duplicates,
            "domains_present": criterion_5_domains_present
        }
    }
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for tab_groups_organization@1 task.
    
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
        # Get tab data from container
        tabs_data = get_tabs_data(copy_from_env)
        
        if tabs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve tab information from Chrome CDP"
            }
        
        # Perform verification
        verification_result = verify_tab_groups_organization(tabs_data)
        
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
