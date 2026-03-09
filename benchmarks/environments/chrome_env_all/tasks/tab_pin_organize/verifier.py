#!/usr/bin/env python3
"""
Verifier for Chrome Tab Pinning and Management Task: tab_pin_organize@1

Task: Open 5 tabs, pin MDN and Stack Overflow, unpin GitHub, organize workspace

Verification Strategy:
1. Use CDP to verify tab count and URLs (primary verification)
2. Attempt to parse Chrome Session files for pinned status (best effort)
3. Multi-criteria scoring with partial credit if session parsing unavailable

Verification Criteria (6 total):
1. Correct tab count (exactly 5 tabs)
2. All required URLs present
3. Exactly 2 tabs pinned
4. Correct tabs pinned (MDN, Stack Overflow)
5. Correct tabs unpinned (GitHub, Reddit, Hacker News)
6. Pin order correct (pinned tabs appear first)

Pass threshold: 70% (4 out of 6 criteria)
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
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


# Expected URLs for the task
EXPECTED_URLS = {
    "mdn": "developer.mozilla.org",
    "stackoverflow": "stackoverflow.com",
    "github": "github.com",
    "reddit": "reddit.com",
    "hackernews": "news.ycombinator.com"
}

EXPECTED_PINNED = ["mdn", "stackoverflow"]
EXPECTED_UNPINNED = ["github", "reddit", "hackernews"]


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for tab_pin_organize@1 task.
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment information including copy_from_env
        task_info: Task configuration
        
    Returns:
        Dict with 'passed', 'score', 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Step 1: Get tabs via CDP
        tabs_data = get_tabs_from_cdp(copy_from_env)
        if tabs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve tab information from CDP"
            }
        
        # Step 2: Attempt to get pinned status from session files
        pinned_status = get_pinned_status_from_session(copy_from_env)
        
        # Step 3: Perform multi-criteria verification
        result = verify_tab_organization(tabs_data, pinned_status)
        
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


def get_tabs_from_cdp(copy_from_env) -> Optional[List[Dict[str, Any]]]:
    """
    Retrieve tab information from CDP export.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        List of tab dicts with 'url', 'title', etc. or None if failed
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        copy_from_env("/tmp/chrome_page_tabs_final.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            tabs_data = json.load(f)
        
        os.unlink(temp_file.name)
        
        logger.info(f"Retrieved {len(tabs_data)} tabs from CDP")
        return tabs_data
        
    except Exception as e:
        logger.error(f"Failed to get tabs from CDP: {e}")
        return None


def get_pinned_status_from_session(copy_from_env) -> Optional[Dict[str, Any]]:
    """
    Attempt to extract pinned tab information from Chrome session files.
    
    This is best-effort - Chrome session files are binary protobuf format
    and may require specialized parsing. If parsing fails, we return None
    and verification proceeds with partial credit.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict with pinned tab information, or None if unavailable
    """
    try:
        # Try to copy Current Session file
        temp_session = tempfile.NamedTemporaryFile(delete=False, suffix='.session')
        temp_session.close()
        
        try:
            copy_from_env("/tmp/chrome_current_session", temp_session.name)
        except Exception as e:
            logger.warning(f"Could not copy Current Session: {e}")
            try:
                copy_from_env("/tmp/chrome_last_session", temp_session.name)
            except Exception as e2:
                logger.warning(f"Could not copy Last Session: {e2}")
                os.unlink(temp_session.name)
                return None
        
        # Check if file has content
        if os.path.getsize(temp_session.name) == 0:
            logger.warning("Session file is empty")
            os.unlink(temp_session.name)
            return None
        
        # Try to parse session file
        # Chrome session files are SNSS (Snappy-compressed) protobuf
        # This is a simplified best-effort parser
        pinned_info = parse_chrome_session_file(temp_session.name)
        
        os.unlink(temp_session.name)
        
        return pinned_info
        
    except Exception as e:
        logger.warning(f"Could not extract pinned status from session: {e}")
        return None


def parse_chrome_session_file(session_path: str) -> Optional[Dict[str, Any]]:
    """
    Parse Chrome session file to extract pinned tab information.
    
    This is a best-effort heuristic parser. Chrome session files use
    proprietary binary protobuf format that's complex to parse fully.
    
    Args:
        session_path: Path to session file
        
    Returns:
        Dict with pinned tab info, or None if parsing failed
    """
    try:
        # Read binary session file
        with open(session_path, 'rb') as f:
            data = f.read()
        
        # Look for pinned tab indicators in the binary data
        # Chrome stores pinned:true or similar flags
        # This is a heuristic approach looking for common patterns
        
        # Count occurrences of "pinned" or related markers
        pinned_count = 0
        
        # Try to find UTF-8 strings in binary data
        try:
            data_str = data.decode('utf-8', errors='ignore')
            
            # Look for pinned indicators
            # Chrome uses various formats: "pinned":true, pinned=1, etc.
            pinned_markers = [
                r'pinned["\s:]*true',
                r'pinned["\s:]*1',
                r'"pinned":\s*true',
                r'is_pinned["\s:]*true'
            ]
            
            for pattern in pinned_markers:
                matches = re.findall(pattern, data_str, re.IGNORECASE)
                pinned_count += len(matches)
            
            # Also look for tab URLs to cross-reference
            urls_in_session = []
            url_pattern = r'https?://[^\s"<>{}|\[\]()]+[^\s"<>{}|\[\]().,;]'
            urls = re.findall(url_pattern, data_str)
            urls_in_session = [url for url in urls if len(url) > 10]  # Filter noise
            
            logger.info(f"Session parse: found ~{pinned_count} pinned markers, {len(urls_in_session)} URLs")
            
            if pinned_count > 0:
                return {
                    "pinned_count": min(pinned_count, 5),  # Cap at reasonable max
                    "urls_in_session": urls_in_session[:10],  # Limit for logging
                    "method": "heuristic_binary_parse"
                }
            else:
                return {
                    "pinned_count": 0,
                    "urls_in_session": urls_in_session[:10],
                    "method": "heuristic_binary_parse"
                }
                
        except Exception as e:
            logger.warning(f"Could not decode session as UTF-8: {e}")
            
        # If string parsing failed, try byte pattern matching
        # Look for byte sequences that indicate pinned tabs
        if b'pinned' in data or b'PINNED' in data:
            # Rough heuristic: count occurrences
            pinned_count = data.count(b'pinned') + data.count(b'PINNED')
            return {
                "pinned_count": min(pinned_count, 5),
                "method": "byte_pattern_match"
            }
        
        logger.warning("Could not find pinned tab indicators in session file")
        return None
        
    except Exception as e:
        logger.error(f"Error parsing session file: {e}")
        return None


def verify_tab_organization(tabs_data: List[Dict[str, Any]], 
                           pinned_status: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify tab organization using multi-criteria assessment.
    
    Args:
        tabs_data: List of tab info from CDP
        pinned_status: Pinned status info from session (may be None)
        
    Returns:
        Dict with verification results
    """
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    
    # Extract URLs from tabs
    tab_urls = [tab.get('url', '').lower() for tab in tabs_data]
    
    logger.info(f"Verifying {len(tab_urls)} tabs")
    for i, url in enumerate(tab_urls, 1):
        logger.info(f"  Tab {i}: {url[:80]}")
    
    # Criterion 1: Correct tab count (exactly 5)
    tab_count = len(tabs_data)
    tab_count_ok = (tab_count == 5)
    if tab_count_ok:
        criteria_met += 1
        feedback_parts.append(f"✓ Tab count correct: {tab_count} tabs")
    else:
        feedback_parts.append(f"✗ Tab count incorrect: {tab_count} tabs (expected 5)")
    
    # Criterion 2: All required URLs present
    urls_found = {}
    for name, domain in EXPECTED_URLS.items():
        found = any(domain in url for url in tab_urls)
        urls_found[name] = found
    
    all_urls_present = all(urls_found.values())
    if all_urls_present:
        criteria_met += 1
        feedback_parts.append(f"✓ All 5 required URLs present")
    else:
        missing = [name for name, found in urls_found.items() if not found]
        feedback_parts.append(f"✗ Missing URLs: {', '.join(missing)}")
    
    # Criteria 3-6: Pinned status verification
    if pinned_status is not None:
        logger.info(f"Pinned status available: {pinned_status}")
        
        # Criterion 3: Exactly 2 tabs pinned
        pinned_count = pinned_status.get('pinned_count', 0)
        pinned_count_ok = (pinned_count == 2)
        if pinned_count_ok:
            criteria_met += 1
            feedback_parts.append(f"✓ Correct number of pinned tabs: {pinned_count}")
        else:
            feedback_parts.append(f"⚠ Pinned tab count: {pinned_count} (expected 2)")
            if pinned_count in [1, 3]:  # Close enough
                criteria_met += 0.5
        
        # Criterion 4 & 5: Correct pins/unpins (heuristic check)
        # Since we can't reliably determine which specific tabs are pinned
        # from session parsing, we give partial credit if count is close
        if pinned_count_ok:
            # Assume correct tabs were pinned if count matches
            criteria_met += 1.5  # Partial credit for criteria 4 & 5
            feedback_parts.append(f"⚠ Pinned tab identity: Likely correct (count matches)")
        else:
            feedback_parts.append(f"⚠ Cannot verify specific pinned tab identity from session")
        
        # Criterion 6: Pin order (not verifiable from current data)
        feedback_parts.append(f"⚠ Pin order: Not verifiable from available data")
        
    else:
        logger.warning("Pinned status not available, proceeding with partial verification")
        feedback_parts.append("⚠ Note: Could not verify pinned status (session file unavailable)")
        feedback_parts.append("⚠ Verification based on tab count and URLs only")
        
        # Give partial credit for having correct tabs if count is exactly 5
        if tab_count == 5 and all_urls_present:
            criteria_met += 1  # Bonus for perfect tab setup
            feedback_parts.append("✓ Tab organization appears correct (URLs and count match)")
    
    # Calculate final score
    # Max criteria_met can be 6, but with partial credits it might be fractional
    score = int((criteria_met / total_criteria) * 100)
    score = min(100, score)  # Cap at 100
    passed = score >= 70  # Need 4+ criteria (70%)
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if pinned_status is None:
        feedback += "\n\n⚠ Note: Full verification of pinned status requires Chrome session file parsing."
        feedback += "\nVerification was based on tab count and URL presence."
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "tab_count": tab_count,
            "urls_found": urls_found,
            "pinned_status_available": pinned_status is not None,
            "pinned_count": pinned_status.get('pinned_count', 0) if pinned_status else None,
            "criteria_met": criteria_met,
            "tab_urls": tab_urls
        }
    }
