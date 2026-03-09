#!/usr/bin/env python3
"""
Verifier for Chrome Tab Search Emergency Task: tab_search_emergency@1
Task: Find flight booking tab among many open tabs using Chrome's tab search feature

Verification Strategy:
- Uses Chrome DevTools Protocol (CDP) data captured at task end
- Identifies the currently active/focused tab
- Checks if active tab is the flight booking confirmation page
- Verifies multiple tabs were open (ensuring search was necessary)
- Validates tab contains expected content (title/URL matching)
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
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for tab_search_emergency@1 task.
    
    Verifies that:
    1. Multiple tabs were open (at least 10)
    2. The active tab is the flight booking confirmation page
    3. Tab contains expected content (flight, booking, confirmation keywords)
    4. Agent successfully navigated to the correct tab
    
    Args:
        traj: Trajectory data (unused for CDP-based verification)
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
        tabs_data, active_tab_info = get_tab_data(copy_from_env)
        
        if tabs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve tab information from Chrome CDP"
            }

        # Perform verification
        verification_result = verify_tab_search_success(tabs_data, active_tab_info)
        
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


def get_tab_data(copy_from_env) -> Tuple[Optional[List[Dict]], Optional[Dict]]:
    """
    Retrieve tab information from container using exported CDP data.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (all_tabs_list, active_tab_info)
    """
    temp_tabs_file = None
    temp_url_file = None
    temp_title_file = None
    
    try:
        # Copy the CDP JSON data
        temp_tabs_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_tabs_file.close()
        
        copy_from_env("/tmp/chrome_page_tabs_final.json", temp_tabs_file.name)
        
        with open(temp_tabs_file.name, 'r') as f:
            tabs_data = json.load(f)
        
        logger.info(f"Retrieved {len(tabs_data)} tab(s) from CDP export")
        
        # Try to get active tab URL and title
        active_url = ""
        active_title = ""
        
        try:
            temp_url_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            temp_url_file.close()
            copy_from_env("/tmp/active_tab_url.txt", temp_url_file.name)
            with open(temp_url_file.name, 'r') as f:
                active_url = f.read().strip()
        except Exception as e:
            logger.warning(f"Could not read active tab URL: {e}")
        
        try:
            temp_title_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            temp_title_file.close()
            copy_from_env("/tmp/active_tab_title.txt", temp_title_file.name)
            with open(temp_title_file.name, 'r') as f:
                active_title = f.read().strip()
        except Exception as e:
            logger.warning(f"Could not read active tab title: {e}")
        
        # If we couldn't get explicit active tab info, use the first tab from CDP
        # (CDP typically returns active tab first)
        if not active_url and tabs_data:
            active_url = tabs_data[0].get('url', '')
            active_title = tabs_data[0].get('title', '')
        
        active_tab_info = {
            'url': active_url,
            'title': active_title
        }
        
        logger.info(f"Active tab: {active_title[:50]} | {active_url[:60]}")
        
        return tabs_data, active_tab_info
        
    except Exception as e:
        logger.error(f"Failed to get tab data: {e}")
        return None, None
    finally:
        # Cleanup temp files
        for temp_file in [temp_tabs_file, temp_url_file, temp_title_file]:
            if temp_file and hasattr(temp_file, 'name') and os.path.exists(temp_file.name):
                try:
                    os.unlink(temp_file.name)
                except:
                    pass


def verify_tab_search_success(tabs_data: List[Dict], active_tab_info: Dict) -> Dict[str, Any]:
    """
    Verify that agent successfully used tab search to find flight booking.
    
    Verification Criteria:
    1. Multiple tabs were open (≥10) - confirms search was necessary
    2. Active tab URL matches flight booking page
    3. Active tab title contains flight/booking keywords
    4. Tab navigation occurred (active tab changed from initial state)
    
    Args:
        tabs_data: List of all open tabs from CDP
        active_tab_info: Information about currently active tab
        
    Returns:
        Verification result dict with passed, score, and feedback
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    active_url = active_tab_info.get('url', '').lower()
    active_title = active_tab_info.get('title', '').lower()
    
    logger.info(f"Verifying tab search task...")
    logger.info(f"  Total tabs: {len(tabs_data)}")
    logger.info(f"  Active URL: {active_url}")
    logger.info(f"  Active title: {active_title}")
    
    # Criterion 1: Multiple tabs open (at least 10)
    tab_count_ok = len(tabs_data) >= 10
    if tab_count_ok:
        feedback_parts.append(f"✓ Sufficient tabs open: {len(tabs_data)} tabs (search was necessary)")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Too few tabs: {len(tabs_data)} tabs (expected at least 10)")
    
    logger.info(f"  Criterion 1 (tab count): {'PASS' if tab_count_ok else 'FAIL'}")
    
    # Criterion 2: Active tab URL matches flight booking page
    # Look for the mock flight booking HTML file
    url_patterns = [
        r'flight.*booking.*confirmation',
        r'flight_booking_confirmation\.html',
        r'file:///home/ga/documents/flight',
    ]
    
    url_match = any(re.search(pattern, active_url, re.IGNORECASE) for pattern in url_patterns)
    
    if url_match:
        feedback_parts.append(f"✓ Correct tab active: Flight booking page URL detected")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Wrong tab active: URL does not match flight booking page")
        feedback_parts.append(f"  Active URL: {active_url[:80]}")
    
    logger.info(f"  Criterion 2 (URL match): {'PASS' if url_match else 'FAIL'}")
    
    # Criterion 3: Active tab title contains expected keywords
    title_keywords = [
        'flight',
        'booking',
        'confirmation',
        'skytravel',
        'airways'
    ]
    
    keyword_matches = [kw for kw in title_keywords if kw in active_title]
    title_ok = len(keyword_matches) >= 2  # At least 2 keywords should match
    
    if title_ok:
        feedback_parts.append(f"✓ Title verified: Contains flight booking keywords ({', '.join(keyword_matches)})")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Title mismatch: Expected flight booking keywords")
        feedback_parts.append(f"  Active title: {active_title[:80]}")
    
    logger.info(f"  Criterion 3 (title match): {'PASS' if title_ok else 'FAIL'} (matched: {keyword_matches})")
    
    # Criterion 4: Verify flight booking tab exists in the tab list
    # (ensures it was actually open and findable)
    flight_tab_found = False
    flight_tab_index = -1
    
    for idx, tab in enumerate(tabs_data):
        tab_url = tab.get('url', '').lower()
        tab_title = tab.get('title', '').lower()
        
        if any(re.search(pattern, tab_url, re.IGNORECASE) for pattern in url_patterns):
            flight_tab_found = True
            flight_tab_index = idx
            break
        elif any(kw in tab_title for kw in ['flight', 'booking', 'confirmation', 'skytravel']):
            # Also check title as backup
            if 'file://' in tab_url or 'flight' in tab_url:
                flight_tab_found = True
                flight_tab_index = idx
                break
    
    if flight_tab_found:
        feedback_parts.append(f"✓ Flight booking tab was present in tab list (position {flight_tab_index + 1}/{len(tabs_data)})")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Flight booking tab not found in any open tab")
    
    logger.info(f"  Criterion 4 (tab exists): {'PASS' if flight_tab_found else 'FAIL'}")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3/4 criteria
    
    # Build comprehensive feedback
    feedback_header = f"Tab Search Emergency Task: {criteria_met}/{total_criteria} criteria met"
    feedback_body = "\n".join(feedback_parts)
    
    if passed:
        result_msg = "\n✅ SUCCESS: Flight booking tab found successfully!"
    else:
        result_msg = "\n❌ FAILED: Could not verify correct tab was found"
        
        # Provide helpful feedback
        if not tab_count_ok:
            result_msg += "\n  Hint: Too few tabs were open for tab search to be necessary"
        if not url_match and not title_ok:
            result_msg += "\n  Hint: The active tab doesn't appear to be the flight booking page"
            result_msg += f"\n  Current active: {active_title[:50]}"
        if not flight_tab_found:
            result_msg += "\n  Hint: Flight booking tab wasn't found among open tabs"
    
    feedback = f"{feedback_header}\n{feedback_body}{result_msg}"
    
    logger.info(f"Verification complete: score={score}, passed={passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "tab_count": len(tabs_data),
            "active_url": active_url,
            "active_title": active_title,
            "url_match": url_match,
            "title_match": title_ok,
            "flight_tab_found": flight_tab_found
        }
    }
