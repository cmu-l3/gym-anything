#!/usr/bin/env python3
"""
Verifier for Chrome Recently Closed Tabs Restoration Task
Task: Restore previously closed tabs (Wikipedia and GitHub) using Recently Closed feature

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) to query all open tabs
- Verifies exactly 3 tabs are open (example.com + restored wikipedia.org + github.com)
- Checks that all expected domains are present
- Validates tab titles to confirm pages loaded correctly
- Ensures no error pages or duplicate URLs
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using standalone mode")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        """Fallback cleanup function"""
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for recently_closed_restore@1 task.
    
    Verifies that:
    1. Exactly 3 tabs are open
    2. example.com tab is present
    3. wikipedia.org tab is present
    4. github.com tab is present
    5. All tabs are properly loaded (no errors)
    
    Pass threshold: 75% (4 out of 5 criteria)
    
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
            "feedback": "copy_from_env function not available - cannot verify task"
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
        verification_result = verify_tab_restoration(tabs_data)
        
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
        Returns None if retrieval fails
    """
    temp_file = None
    try:
        # Copy the CDP JSON data from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations for the tab data
        possible_paths = [
            "/tmp/chrome_page_tabs.json",
            "/tmp/chrome_all_tabs.json"
        ]
        
        tabs_data = None
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy tab data from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r') as f:
                        data = json.load(f)
                    
                    # Filter to page-type tabs if needed
                    if isinstance(data, list):
                        if len(data) > 0 and 'type' in data[0]:
                            tabs_data = [t for t in data if t.get('type') == 'page']
                        else:
                            tabs_data = data
                    
                    logger.info(f"✓ Successfully retrieved {len(tabs_data)} tab(s) from {container_path}")
                    break
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if tabs_data is None:
            logger.error("Could not retrieve tab data from any location")
            return None
        
        return tabs_data
        
    except Exception as e:
        logger.error(f"Failed to get tabs data: {e}", exc_info=True)
        return None
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison.
    
    Args:
        url: URL string to normalize
        
    Returns:
        Normalized URL string (lowercase, no protocol, no trailing slash)
    """
    if not url:
        return ""
    
    # Convert to lowercase
    url = url.lower()
    
    # Remove protocol
    url = url.replace('https://', '').replace('http://', '')
    
    # Remove www. prefix
    url = url.replace('www.', '')
    
    # Remove trailing slash
    url = url.rstrip('/')
    
    # Remove query parameters and fragments for cleaner matching
    url = url.split('?')[0].split('#')[0]
    
    return url


def check_domain_in_url(url: str, domain: str) -> bool:
    """
    Check if a domain is present in a URL.
    
    Args:
        url: Full URL to check
        domain: Domain to look for (e.g., "example.com")
        
    Returns:
        True if domain is found in URL, False otherwise
    """
    normalized_url = normalize_url(url)
    normalized_domain = normalize_url(domain)
    
    # Check if domain is at the start (exact match or subdomain)
    if normalized_url.startswith(normalized_domain):
        return True
    
    # Check if domain appears after removing subdomain
    if normalized_domain in normalized_url:
        # Make sure it's not a substring of another domain
        # e.g., "example.com" should match "example.com/path" but not "notexample.com"
        parts = normalized_url.split('/')
        if parts[0] == normalized_domain or parts[0].endswith('.' + normalized_domain):
            return True
    
    return False


def verify_tab_restoration(tabs_data: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify that tabs were correctly restored.
    
    Checks 5 criteria:
    1. Exactly 3 tabs are open
    2. example.com tab is present
    3. wikipedia.org tab is present
    4. github.com tab is present
    5. All tabs are properly loaded (no errors)
    
    Args:
        tabs_data: List of tab information from CDP
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    # Expected domains
    expected_domains = {
        "example.com": False,
        "wikipedia.org": False,
        "github.com": False
    }
    
    # Extract URLs and titles from tabs
    tab_urls = [tab.get('url', '') for tab in tabs_data]
    tab_titles = [tab.get('title', '') for tab in tabs_data]
    
    logger.info(f"Verifying {len(tabs_data)} tab(s)")
    for i, (url, title) in enumerate(zip(tab_urls, tab_titles), 1):
        logger.info(f"  Tab {i}: {url[:80]}...")
        logger.info(f"         Title: {title[:60]}...")
    
    # Criterion 1: Exactly 3 tabs open
    tab_count_ok = len(tabs_data) == 3
    logger.info(f"Criterion 1 - Tab count: {len(tabs_data)} tabs (expected 3) - {'PASS' if tab_count_ok else 'FAIL'}")
    
    # Criteria 2-4: Check each expected domain is present
    for url in tab_urls:
        for domain in expected_domains.keys():
            if check_domain_in_url(url, domain):
                expected_domains[domain] = True
    
    example_present = expected_domains["example.com"]
    wikipedia_present = expected_domains["wikipedia.org"]
    github_present = expected_domains["github.com"]
    
    logger.info(f"Criterion 2 - example.com present: {'PASS' if example_present else 'FAIL'}")
    logger.info(f"Criterion 3 - wikipedia.org present: {'PASS' if wikipedia_present else 'FAIL'}")
    logger.info(f"Criterion 4 - github.com present: {'PASS' if github_present else 'FAIL'}")
    
    # Criterion 5: No error pages
    error_keywords = ["error", "404", "not found", "page not found", "cannot be reached", 
                     "unable to connect", "this site can't be reached", "dns_probe"]
    
    has_errors = False
    error_tabs = []
    for i, (url, title) in enumerate(zip(tab_urls, tab_titles), 1):
        url_lower = url.lower()
        title_lower = title.lower()
        
        # Check for error indicators
        if any(keyword in title_lower for keyword in error_keywords):
            has_errors = True
            error_tabs.append(f"Tab {i}: {title}")
        elif any(keyword in url_lower for keyword in error_keywords):
            has_errors = True
            error_tabs.append(f"Tab {i}: {url}")
        elif "chrome-error://" in url_lower:
            has_errors = True
            error_tabs.append(f"Tab {i}: Chrome error page")
    
    no_errors = not has_errors
    logger.info(f"Criterion 5 - No error pages: {'PASS' if no_errors else 'FAIL'}")
    if has_errors:
        for error_tab in error_tabs:
            logger.warning(f"  Error detected: {error_tab}")
    
    # Calculate score based on criteria met
    criteria_results = [
        tab_count_ok,
        example_present,
        wikipedia_present,
        github_present,
        no_errors
    ]
    
    criteria_met = sum(criteria_results)
    total_criteria = 5
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 4/5 criteria (75%)
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Tab Restoration Verification: {criteria_met}/{total_criteria} criteria met")
    feedback_parts.append("")
    
    # Criterion 1
    if tab_count_ok:
        feedback_parts.append(f"✓ Criterion 1: Exactly 3 tabs open")
    else:
        feedback_parts.append(f"✗ Criterion 1: Found {len(tabs_data)} tabs (expected 3)")
        if len(tabs_data) < 3:
            feedback_parts.append(f"  → Not enough tabs. Did you restore both closed tabs?")
        elif len(tabs_data) > 3:
            feedback_parts.append(f"  → Too many tabs. You may have extra tabs open or duplicates.")
    
    # Criterion 2
    if example_present:
        feedback_parts.append(f"✓ Criterion 2: example.com tab present")
    else:
        feedback_parts.append(f"✗ Criterion 2: example.com tab not found")
        feedback_parts.append(f"  → The original tab should still be open")
    
    # Criterion 3
    if wikipedia_present:
        feedback_parts.append(f"✓ Criterion 3: wikipedia.org tab present (restored)")
    else:
        feedback_parts.append(f"✗ Criterion 3: wikipedia.org tab not found")
        feedback_parts.append(f"  → This tab should be restored from Recently Closed")
    
    # Criterion 4
    if github_present:
        feedback_parts.append(f"✓ Criterion 4: github.com tab present (restored)")
    else:
        feedback_parts.append(f"✗ Criterion 4: github.com tab not found")
        feedback_parts.append(f"  → This tab should be restored from Recently Closed")
    
    # Criterion 5
    if no_errors:
        feedback_parts.append(f"✓ Criterion 5: All tabs loaded correctly")
    else:
        feedback_parts.append(f"✗ Criterion 5: Error pages detected")
        for error_tab in error_tabs:
            feedback_parts.append(f"  → {error_tab}")
    
    feedback_parts.append("")
    feedback_parts.append("="*60)
    
    # Add summary
    if passed:
        feedback_parts.append("✅ PASSED: Tabs successfully restored!")
        if criteria_met == total_criteria:
            feedback_parts.append("   Perfect execution - all criteria met.")
        else:
            feedback_parts.append(f"   Good job, though {total_criteria - criteria_met} criterion needs attention.")
    else:
        feedback_parts.append("❌ FAILED: Tab restoration incomplete")
        missing = total_criteria - criteria_met
        feedback_parts.append(f"   {missing} criteria not met. Please restore both closed tabs.")
    
    feedback_parts.append(f"   Final Score: {score}% ({criteria_met}/{total_criteria})")
    
    # Add helpful hint if failed
    if not passed:
        feedback_parts.append("")
        feedback_parts.append("Hint: To restore closed tabs, you can:")
        feedback_parts.append("  • Press Ctrl+Shift+T twice (once for each closed tab)")
        feedback_parts.append("  • Or click Menu (⋮) → History → Recently closed → Click each tab")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "tab_count": len(tabs_data),
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "domains_found": expected_domains,
            "has_errors": has_errors,
            "tab_urls": tab_urls,
            "tab_titles": tab_titles
        }
    }
