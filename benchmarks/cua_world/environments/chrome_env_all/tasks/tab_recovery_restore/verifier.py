#!/usr/bin/env python3
"""
Verifier for Chrome Tab Recovery Task: tab_recovery_restore@1
Task: Recover 3 accidentally closed research tabs using Chrome's recently-closed feature

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) to query all currently open tabs
- Checks for presence of 3 specific target URLs (Wikipedia, Stack Overflow, GitHub)
- Validates that tabs loaded successfully (not error pages)
- Ensures reasonable tab count (not excessive duplicates or extraneous tabs)
- Provides detailed feedback on which tabs were successfully recovered
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    def cleanup_verification_temp():
        pass


# Target URLs that should be recovered
TARGET_TABS = {
    "wikipedia": {
        "url_keywords": ["wikipedia.org", "quantum"],
        "title_keywords": ["quantum", "computing", "wikipedia"],
        "name": "Wikipedia (Quantum Computing)"
    },
    "stackoverflow": {
        "url_keywords": ["stackoverflow.com", "binary", "search"],
        "title_keywords": ["binary", "search", "python", "stack overflow"],
        "name": "Stack Overflow (Binary Search)"
    },
    "github": {
        "url_keywords": ["github.com", "react"],
        "title_keywords": ["react", "facebook", "github"],
        "name": "GitHub (React Repository)"
    }
}


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for tab_recovery_restore@1 task.
    
    Verifies that the agent successfully recovered the 3 target tabs:
    1. Wikipedia - Quantum Computing
    2. Stack Overflow - Binary search in Python  
    3. GitHub - facebook/react repository
    
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
        tabs_data = get_tabs_data_from_container(copy_from_env)
        if tabs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve tab information from Chrome CDP"
            }

        # Perform multi-criteria verification
        verification_result = verify_tab_recovery(tabs_data)
        
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


def get_tabs_data_from_container(copy_from_env) -> Optional[List[Dict[str, Any]]]:
    """
    Retrieve tab information from container using CDP data.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        List of tab dictionaries with 'url', 'title', and other metadata, or None on failure
    """
    temp_file = None
    try:
        # Copy the CDP JSON data from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        copy_paths = [
            "/tmp/chrome_page_tabs.json",
            "/tmp/tab_recovery_verification/chrome_page_tabs.json"
        ]
        
        success = False
        for copy_path in copy_paths:
            try:
                logger.info(f"Attempting to copy from: {copy_path}")
                copy_from_env(copy_path, temp_path)
                
                # Check if file has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    success = True
                    logger.info(f"✓ Successfully copied from: {copy_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {copy_path}: {e}")
                continue
        
        if not success:
            logger.error("Failed to copy tab data from any location")
            return None
        
        # Parse JSON
        with open(temp_path, 'r') as f:
            tabs_data = json.load(f)
        
        logger.info(f"Successfully retrieved {len(tabs_data)} tab(s) from CDP")
        return tabs_data
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse tab data JSON: {e}")
        return None
    except Exception as e:
        logger.error(f"Failed to get tabs data: {e}")
        return None
    finally:
        # Clean up temp file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def check_tab_match(tab_url: str, tab_title: str, target_config: Dict) -> Tuple[bool, float]:
    """
    Check if a tab matches the target configuration.
    
    Args:
        tab_url: URL of the tab
        tab_title: Title of the tab
        target_config: Configuration dict with url_keywords and title_keywords
        
    Returns:
        Tuple of (is_match: bool, confidence: float)
    """
    url_lower = tab_url.lower()
    title_lower = tab_title.lower()
    
    # Check URL keywords
    url_matches = sum(1 for keyword in target_config["url_keywords"] if keyword.lower() in url_lower)
    url_score = url_matches / len(target_config["url_keywords"])
    
    # Check title keywords (more flexible, any match is good)
    title_matches = sum(1 for keyword in target_config["title_keywords"] if keyword.lower() in title_lower)
    title_score = min(1.0, title_matches / 2)  # Need at least 2 keywords or proportional
    
    # Combined score (URL is more important)
    confidence = (url_score * 0.7) + (title_score * 0.3)
    
    # Consider it a match if confidence >= 0.5 (at least primary URL keyword matches)
    is_match = confidence >= 0.5
    
    return is_match, confidence


def detect_error_page(tab_url: str, tab_title: str) -> bool:
    """
    Detect if a tab is showing an error page.
    
    Args:
        tab_url: URL of the tab
        tab_title: Title of the tab
        
    Returns:
        True if appears to be an error page, False otherwise
    """
    error_indicators = [
        "404", "not found", "error", "cannot be reached",
        "page not found", "site can't be reached", "connection refused",
        "dns_probe", "err_", "unable to connect"
    ]
    
    combined = (tab_url + " " + tab_title).lower()
    return any(indicator in combined for indicator in error_indicators)


def verify_tab_recovery(tabs_data: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify that the 3 target tabs were successfully recovered.
    
    Verification criteria:
    1. Wikipedia tab present and loaded
    2. Stack Overflow tab present and loaded
    3. GitHub tab present and loaded
    4. Reasonable tab count (3-6 tabs, allowing for some extras)
    5. No excessive duplicates of target tabs
    6. No error pages detected
    
    Args:
        tabs_data: List of tab information from CDP
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    # Extract URLs and titles
    tab_urls = [tab.get('url', '') for tab in tabs_data]
    tab_titles = [tab.get('title', '') for tab in tabs_data]
    total_tabs = len(tabs_data)
    
    logger.info(f"Analyzing {total_tabs} tabs for recovery verification")
    for i, (url, title) in enumerate(zip(tab_urls, tab_titles), 1):
        logger.info(f"  Tab {i}: {url[:70]}... | {title[:50]}...")
    
    # Track which targets were found and their confidence
    targets_found = {
        "wikipedia": {"found": False, "confidence": 0.0, "count": 0},
        "stackoverflow": {"found": False, "confidence": 0.0, "count": 0},
        "github": {"found": False, "confidence": 0.0, "count": 0}
    }
    
    # Check each tab against each target
    for url, title in zip(tab_urls, tab_titles):
        for target_key, target_config in TARGET_TABS.items():
            is_match, confidence = check_tab_match(url, title, target_config)
            
            if is_match:
                targets_found[target_key]["found"] = True
                targets_found[target_key]["confidence"] = max(
                    targets_found[target_key]["confidence"],
                    confidence
                )
                targets_found[target_key]["count"] += 1
    
    # Criterion 1-3: Target tabs present
    wikipedia_ok = targets_found["wikipedia"]["found"]
    stackoverflow_ok = targets_found["stackoverflow"]["found"]
    github_ok = targets_found["github"]["found"]
    
    tabs_recovered = sum([wikipedia_ok, stackoverflow_ok, github_ok])
    
    logger.info(f"✓ Target tabs found: {tabs_recovered}/3")
    logger.info(f"  Wikipedia: {'✓' if wikipedia_ok else '✗'} (confidence: {targets_found['wikipedia']['confidence']:.2f})")
    logger.info(f"  Stack Overflow: {'✓' if stackoverflow_ok else '✗'} (confidence: {targets_found['stackoverflow']['confidence']:.2f})")
    logger.info(f"  GitHub: {'✓' if github_ok else '✗'} (confidence: {targets_found['github']['confidence']:.2f})")
    
    # Criterion 4: Reasonable tab count
    # Should have: original 2-3 tabs + 3 recovered = 5-6 tabs typically
    # Allow some flexibility: 4-8 tabs is reasonable
    tab_count_ok = 4 <= total_tabs <= 8
    if not tab_count_ok:
        if total_tabs < 4:
            logger.warning(f"Tab count low: {total_tabs} (expected 4-8)")
        else:
            logger.warning(f"Tab count high: {total_tabs} (expected 4-8, possible duplicates)")
    else:
        logger.info(f"✓ Tab count reasonable: {total_tabs} tabs")
    
    # Criterion 5: No excessive duplicates
    max_duplicates = max(targets_found[key]["count"] for key in targets_found)
    no_excessive_duplicates = max_duplicates <= 2  # Allow up to 2 of same tab
    if not no_excessive_duplicates:
        logger.warning(f"Excessive duplicates detected: max count = {max_duplicates}")
    else:
        logger.info(f"✓ No excessive duplicates (max per tab: {max_duplicates})")
    
    # Criterion 6: No error pages
    error_pages_found = []
    for url, title in zip(tab_urls, tab_titles):
        if detect_error_page(url, title):
            error_pages_found.append(f"{title[:30]}...")
    
    no_errors = len(error_pages_found) == 0
    if not no_errors:
        logger.warning(f"Error pages detected: {error_pages_found}")
    else:
        logger.info("✓ No error pages detected")
    
    # Calculate score
    # Core criteria: 3 target tabs (60% weight) + 3 quality criteria (40% weight)
    core_score = (tabs_recovered / 3.0) * 60  # 0-60 points
    
    quality_criteria = [tab_count_ok, no_excessive_duplicates, no_errors]
    quality_score = (sum(quality_criteria) / 3.0) * 40  # 0-40 points
    
    total_score = int(core_score + quality_score)
    passed = total_score >= 75  # Need 75% or higher
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Tab Recovery Verification: {tabs_recovered}/3 target tabs recovered")
    feedback_parts.append("")
    feedback_parts.append("Target tabs:")
    feedback_parts.append(f"  {'✓' if wikipedia_ok else '✗'} Wikipedia (Quantum Computing) - {targets_found['wikipedia']['count']} instance(s)")
    feedback_parts.append(f"  {'✓' if stackoverflow_ok else '✗'} Stack Overflow (Binary Search) - {targets_found['stackoverflow']['count']} instance(s)")
    feedback_parts.append(f"  {'✓' if github_ok else '✗'} GitHub (React Repository) - {targets_found['github']['count']} instance(s)")
    feedback_parts.append("")
    feedback_parts.append("Quality checks:")
    feedback_parts.append(f"  {'✓' if tab_count_ok else '✗'} Tab count: {total_tabs} tabs (expected 4-8)")
    feedback_parts.append(f"  {'✓' if no_excessive_duplicates else '✗'} No excessive duplicates")
    feedback_parts.append(f"  {'✓' if no_errors else '✗'} No error pages")
    feedback_parts.append("")
    feedback_parts.append(f"Score: {total_score}/100 ({core_score:.0f} core + {quality_score:.0f} quality)")
    
    if passed:
        if tabs_recovered == 3:
            feedback_parts.append("✅ Task completed successfully! All tabs recovered.")
        else:
            feedback_parts.append("✅ Task passed with minor issues.")
    else:
        if tabs_recovered == 0:
            feedback_parts.append("❌ Task failed: No target tabs were recovered.")
            feedback_parts.append("Hint: Use Ctrl+Shift+T or History → Recently closed tabs")
        elif tabs_recovered < 3:
            missing = []
            if not wikipedia_ok:
                missing.append("Wikipedia")
            if not stackoverflow_ok:
                missing.append("Stack Overflow")
            if not github_ok:
                missing.append("GitHub")
            feedback_parts.append(f"❌ Task incomplete: Missing {', '.join(missing)}")
        else:
            feedback_parts.append("❌ Task failed: Quality criteria not met")
    
    feedback = "\n".join(feedback_parts)
    
    logger.info(f"Final result: passed={passed}, score={total_score}")
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback,
        "details": {
            "total_tabs": total_tabs,
            "tabs_recovered": tabs_recovered,
            "targets_found": targets_found,
            "tab_count_ok": tab_count_ok,
            "no_duplicates": no_excessive_duplicates,
            "no_errors": no_errors,
            "error_pages": error_pages_found,
            "tab_urls": tab_urls,
            "tab_titles": tab_titles
        }
    }
