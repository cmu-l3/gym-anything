#!/usr/bin/env python3
"""
Verifier for Chrome Media-Playing Tab Detection Task (find_playing_media_tab@1)
Task: Identify and navigate to the tab that is currently playing media among multiple tabs

Verification Strategy:
1. Use CDP to retrieve all open tabs with their media status
2. Identify which tab(s) have audible media playing
3. Identify which tab is currently active
4. Verify that the active tab is one with playing media
5. Ensure multiple tabs exist for a valid test scenario
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

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for find_playing_media_tab@1 task.
    
    Verifies that the agent successfully identified and navigated to the tab
    with playing media among multiple open tabs.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed' (bool), 'score' (int 0-100), and 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Get tab information from container
        tabs_data, media_tabs_data, active_tab_info = get_all_tab_data(copy_from_env)
        
        if tabs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve tab information from Chrome CDP"
            }
        
        # Perform verification
        result = verify_media_tab_navigation(tabs_data, media_tabs_data, active_tab_info)
        
        # Clean up temporary files
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


def get_all_tab_data(copy_from_env) -> Tuple[Optional[List[Dict]], Optional[List[Dict]], Optional[Dict]]:
    """
    Retrieve all tab information from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (all_tabs, media_tabs, active_tab_info)
    """
    all_tabs = None
    media_tabs = None
    active_tab_info = {}
    
    try:
        # Copy all tabs data
        temp_all = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_all.close()
        
        copy_from_env("/tmp/chrome_page_tabs.json", temp_all.name)
        with open(temp_all.name, 'r') as f:
            all_tabs = json.load(f)
        os.unlink(temp_all.name)
        
        logger.info(f"Retrieved {len(all_tabs)} total tab(s)")
        
    except Exception as e:
        logger.error(f"Failed to get all tabs data: {e}")
        return None, None, None
    
    try:
        # Copy media tabs data
        temp_media = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_media.close()
        
        copy_from_env("/tmp/media_tabs.json", temp_media.name)
        with open(temp_media.name, 'r') as f:
            media_tabs = json.load(f)
        os.unlink(temp_media.name)
        
        logger.info(f"Retrieved {len(media_tabs)} media tab(s)")
        
    except Exception as e:
        logger.warning(f"Failed to get media tabs data: {e}")
        media_tabs = []
    
    try:
        # Get active tab URL
        temp_url = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_url.close()
        
        copy_from_env("/tmp/active_tab_url.txt", temp_url.name)
        with open(temp_url.name, 'r') as f:
            active_tab_info['url'] = f.read().strip()
        os.unlink(temp_url.name)
        
        # Get active tab title
        temp_title = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_title.close()
        
        copy_from_env("/tmp/active_tab_title.txt", temp_title.name)
        with open(temp_title.name, 'r') as f:
            active_tab_info['title'] = f.read().strip()
        os.unlink(temp_title.name)
        
        logger.info(f"Active tab: {active_tab_info.get('title', 'unknown')}")
        
    except Exception as e:
        logger.warning(f"Failed to get active tab info: {e}")
        active_tab_info = {'url': 'unknown', 'title': 'unknown'}
    
    return all_tabs, media_tabs, active_tab_info


def verify_media_tab_navigation(
    all_tabs: List[Dict[str, Any]],
    media_tabs: List[Dict[str, Any]],
    active_tab_info: Dict[str, str]
) -> Dict[str, Any]:
    """
    Verify that agent navigated to a media-playing tab.
    
    Verification Criteria:
    1. Multiple tabs exist (minimum 3)
    2. At least one tab has audible media
    3. Active tab is one of the media-playing tabs
    4. Active tab URL matches a media tab URL
    5. Media tab detection is robust
    
    Args:
        all_tabs: List of all tab data from CDP
        media_tabs: List of tabs with audible media
        active_tab_info: Information about currently active tab
        
    Returns:
        Verification result dict
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: Multiple tabs exist
    tab_count = len(all_tabs)
    multiple_tabs_ok = tab_count >= 3
    
    if multiple_tabs_ok:
        feedback_parts.append(f"✓ Multiple tabs present: {tab_count} tabs")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Insufficient tabs: {tab_count} tabs (need at least 3)")
    
    logger.info(f"Criterion 1 - Tab count: {tab_count} - {'PASS' if multiple_tabs_ok else 'FAIL'}")
    
    # Criterion 2: At least one media tab exists
    media_tab_count = len(media_tabs)
    media_exists = media_tab_count >= 1
    
    if media_exists:
        feedback_parts.append(f"✓ Media tab detected: {media_tab_count} tab(s) with audible media")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ No media playing tabs detected (setup may have failed)")
        # If no media tabs, task cannot succeed
        return {
            "passed": False,
            "score": 0,
            "feedback": "\n".join(feedback_parts) + "\n\n❌ Task cannot be completed - no media playing in any tab",
            "details": {
                "tab_count": tab_count,
                "media_tab_count": media_tab_count,
                "criteria_met": criteria_met
            }
        }
    
    logger.info(f"Criterion 2 - Media tabs: {media_tab_count} - {'PASS' if media_exists else 'FAIL'}")
    
    # Criterion 3: Active tab identification
    active_url = active_tab_info.get('url', '').lower()
    active_title = active_tab_info.get('title', '')
    
    active_identified = active_url != 'unknown' and len(active_url) > 0
    
    if active_identified:
        feedback_parts.append(f"✓ Active tab identified: {active_title[:50]}...")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Could not identify active tab")
    
    logger.info(f"Criterion 3 - Active tab identified: {active_identified} - {'PASS' if active_identified else 'FAIL'}")
    
    # Criterion 4: Active tab is a media tab
    media_urls = [tab.get('url', '').lower() for tab in media_tabs]
    
    # Normalize URLs for comparison
    normalized_active = normalize_url(active_url)
    normalized_media_urls = [normalize_url(url) for url in media_urls]
    
    active_is_media = normalized_active in normalized_media_urls
    
    if active_is_media:
        feedback_parts.append(f"✓ Active tab is playing media: Correct identification!")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Active tab is NOT playing media")
        feedback_parts.append(f"  Current active: {active_title[:40]}")
        if media_tabs:
            media_title = media_tabs[0].get('title', 'unknown')
            feedback_parts.append(f"  Media playing in: {media_title[:40]}")
    
    logger.info(f"Criterion 4 - Active is media tab: {active_is_media} - {'PASS' if active_is_media else 'FAIL'}")
    
    # Criterion 5: Robust detection (check the active tab in all_tabs also has audible flag)
    robust_detection = False
    for tab in all_tabs:
        tab_url = tab.get('url', '').lower()
        if normalize_url(tab_url) == normalized_active:
            if tab.get('audible', False):
                robust_detection = True
                break
    
    if robust_detection:
        feedback_parts.append(f"✓ Robust verification: Active tab confirmed audible in real-time")
        criteria_met += 1
    else:
        if active_is_media:
            feedback_parts.append(f"⚠ Active tab matched but audible flag not set (may be timing issue)")
            criteria_met += 0.5  # Partial credit
        else:
            feedback_parts.append(f"✗ Robust verification failed")
    
    logger.info(f"Criterion 5 - Robust detection: {robust_detection} - {'PASS' if robust_detection else 'FAIL'}")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3.75/5 criteria
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'✅ PASSED' if passed else '❌ FAILED'}"
    
    if passed:
        feedback += "\n\nExcellent! You successfully identified and navigated to the media-playing tab."
    else:
        feedback += "\n\nTask incomplete. The active tab is not the one playing media."
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "tab_count": tab_count,
            "media_tab_count": media_tab_count,
            "criteria_met": criteria_met,
            "active_tab": active_title,
            "active_is_media": active_is_media,
            "robust_detection": robust_detection
        }
    }


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison.
    
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
    url = url.replace('https://', '').replace('http://', '').replace('file://', '')
    
    # Remove trailing slashes
    url = url.rstrip('/')
    
    # Remove www. prefix
    url = url.replace('www.', '')
    
    return url
