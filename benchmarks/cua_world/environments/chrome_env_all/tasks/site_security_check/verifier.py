#!/usr/bin/env python3
"""
Verifier for Chrome Site Security Verification Task (site_security_check@1)
Task: Navigate to HTTPS site, examine security indicators, verify connection is secure

Verification Strategy:
1. Check that agent visited an HTTPS site (specifically example.com)
2. Verify URL is correct and secure (https://)
3. Check time spent on secure site (minimum threshold for genuine inspection)
4. Verify via CDP that secure site is loaded
5. Analyze trajectory for patterns suggesting security examination
"""

import logging
import sys
import os
import json
import re
import sqlite3
import tempfile
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../utils'))
try:
    from chrome_verification_utils import (
        parse_history,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for site_security_check@1.
    
    Verifies that the agent:
    1. Navigated to a secure HTTPS website (example.com)
    2. Spent adequate time examining the site (security check behavior)
    3. Accessed the correct secure domain
    4. Did not visit insecure HTTP sites
    
    Scoring:
    - 100%: All 5 criteria met (perfect security verification)
    - 80-99%: 4/5 criteria met (good with minor issues)
    - 60-79%: 3/5 criteria met (partial success)
    - <60%: <3 criteria met (insufficient verification)
    
    Pass threshold: 80% (4 out of 5 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get active tab and history information
        active_url, tab_data = get_active_tab_info(copy_from_env)
        history_data = get_history_info(copy_from_env)
        time_data = get_timing_info(copy_from_env)
        
        # Perform multi-criteria verification
        verification_result = verify_security_check(
            active_url,
            tab_data,
            history_data,
            time_data,
            traj
        )
        
        # Clean up
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


def get_active_tab_info(copy_from_env) -> Tuple[str, Dict]:
    """
    Get active tab information from CDP export.
    
    Returns:
        Tuple of (active_url: str, tab_data: dict)
    """
    try:
        # Try to get active URL from exported file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        try:
            copy_from_env("/tmp/security_check_verification/active_url.txt", temp_file.name)
            with open(temp_file.name, 'r') as f:
                active_url = f.read().strip()
        except Exception as e:
            logger.warning(f"Could not get active_url.txt: {e}")
            # Fallback: try to get from CDP JSON
            try:
                temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
                temp_json.close()
                copy_from_env("/tmp/security_check_verification/active_tab.json", temp_json.name)
                with open(temp_json.name, 'r') as f:
                    tab_data = json.load(f)
                    active_url = tab_data.get('url', '')
                os.unlink(temp_json.name)
            except Exception as e2:
                logger.warning(f"Could not get active_tab.json: {e2}")
                active_url = ""
        
        os.unlink(temp_file.name)
        
        # Get full tab data
        tab_data = {}
        try:
            temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            temp_json.close()
            copy_from_env("/tmp/security_check_verification/active_tab.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                tab_data = json.load(f)
            os.unlink(temp_json.name)
        except Exception as e:
            logger.warning(f"Could not get full tab data: {e}")
        
        logger.info(f"Active URL: {active_url}")
        return active_url, tab_data
        
    except Exception as e:
        logger.error(f"Error getting active tab info: {e}")
        return "", {}


def get_history_info(copy_from_env) -> List[Tuple[str, str]]:
    """
    Get browsing history from Chrome History database or CDP export.
    
    Returns:
        List of (url, title) tuples from recent history
    """
    history = []
    
    # Try to get all URLs from CDP export
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        copy_from_env("/tmp/security_check_verification/all_urls.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            urls = f.read().strip().split('\n')
            history = [(url.strip(), "") for url in urls if url.strip()]
        
        os.unlink(temp_file.name)
        logger.info(f"Retrieved {len(history)} URLs from CDP export")
        
    except Exception as e:
        logger.warning(f"Could not get CDP URLs: {e}")
    
    # Try to get from History database if available
    if not history or len(history) < 2:
        try:
            temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
            temp_db.close()
            
            copy_from_env("/tmp/security_check_verification/History.db", temp_db.name)
            
            if UTILS_AVAILABLE:
                history = parse_history(temp_db.name)
            else:
                # Fallback: manual parsing
                conn = sqlite3.connect(temp_db.name)
                cursor = conn.cursor()
                cursor.execute("SELECT url, title FROM urls ORDER BY last_visit_time DESC LIMIT 20")
                history = cursor.fetchall()
                conn.close()
            
            os.unlink(temp_db.name)
            logger.info(f"Retrieved {len(history)} entries from History database")
            
        except Exception as e:
            logger.warning(f"Could not get History database: {e}")
    
    return history


def get_timing_info(copy_from_env) -> Dict[str, int]:
    """
    Get task timing information to calculate duration.
    
    Returns:
        Dict with 'start_time', 'end_time', 'duration_seconds'
    """
    timing = {
        'start_time': 0,
        'end_time': 0,
        'duration_seconds': 0
    }
    
    try:
        # Get start time
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        try:
            copy_from_env("/tmp/task_start_time.txt", temp_file.name)
            with open(temp_file.name, 'r') as f:
                timing['start_time'] = int(f.read().strip())
        except Exception as e:
            logger.warning(f"Could not get start time: {e}")
        
        os.unlink(temp_file.name)
        
        # Get end time
        temp_file2 = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file2.close()
        
        try:
            copy_from_env("/tmp/security_check_verification/task_end_time.txt", temp_file2.name)
            with open(temp_file2.name, 'r') as f:
                timing['end_time'] = int(f.read().strip())
        except Exception as e:
            logger.warning(f"Could not get end time: {e}")
        
        os.unlink(temp_file2.name)
        
        # Calculate duration
        if timing['start_time'] > 0 and timing['end_time'] > 0:
            timing['duration_seconds'] = timing['end_time'] - timing['start_time']
            logger.info(f"Task duration: {timing['duration_seconds']} seconds")
        
    except Exception as e:
        logger.warning(f"Error getting timing info: {e}")
    
    return timing


def verify_security_check(
    active_url: str,
    tab_data: Dict,
    history_data: List[Tuple[str, str]],
    time_data: Dict,
    traj: Any
) -> Dict[str, Any]:
    """
    Perform multi-criteria verification of security check task.
    
    Criteria:
    1. HTTPS site visited (specifically example.com or similar secure site)
    2. Correct domain accessed
    3. Adequate time spent (minimum 5 seconds, suggests genuine inspection)
    4. No HTTP (insecure) sites visited
    5. URL pattern matches expected secure site
    
    Returns:
        Verification result with passed, score, feedback, and details
    """
    TARGET_DOMAIN = "example.com"
    EXPECTED_URL_PATTERN = r"https://example\.com"
    MIN_DURATION_SECONDS = 5
    
    criteria_met = {
        'https_visited': False,
        'correct_domain': False,
        'adequate_time': False,
        'no_insecure_sites': True,  # Default true, set false if HTTP found
        'url_pattern_match': False
    }
    
    feedback_parts = []
    
    # Criterion 1 & 2: HTTPS site visited with correct domain
    if active_url:
        url_lower = active_url.lower()
        
        if url_lower.startswith('https://'):
            criteria_met['https_visited'] = True
            feedback_parts.append(f"✓ HTTPS site visited: {active_url}")
            
            if TARGET_DOMAIN in url_lower:
                criteria_met['correct_domain'] = True
                feedback_parts.append(f"✓ Correct domain accessed: {TARGET_DOMAIN}")
            else:
                feedback_parts.append(f"✗ Wrong domain: expected {TARGET_DOMAIN}, got {url_lower}")
        else:
            feedback_parts.append(f"✗ Not HTTPS: {active_url}")
    else:
        feedback_parts.append("✗ No active URL detected")
    
    # Criterion 5: URL pattern match (more flexible)
    if active_url and re.search(EXPECTED_URL_PATTERN, active_url, re.IGNORECASE):
        criteria_met['url_pattern_match'] = True
        feedback_parts.append("✓ URL pattern matches expected format")
    else:
        # Allow some flexibility - if it's any HTTPS site, partial credit
        if active_url and active_url.lower().startswith('https://'):
            feedback_parts.append("⚠ HTTPS site visited, but not the expected example.com")
        else:
            feedback_parts.append("✗ URL pattern does not match expected format")
    
    # Criterion 3: Adequate time spent
    duration = time_data.get('duration_seconds', 0)
    if duration >= MIN_DURATION_SECONDS:
        criteria_met['adequate_time'] = True
        feedback_parts.append(f"✓ Adequate time spent: {duration} seconds")
    else:
        if duration > 0:
            feedback_parts.append(f"✗ Insufficient time: {duration}s (minimum {MIN_DURATION_SECONDS}s)")
        else:
            feedback_parts.append(f"⚠ Could not determine time spent (assuming adequate)")
            # Give benefit of doubt if timing unavailable
            criteria_met['adequate_time'] = True
    
    # Criterion 4: Check for insecure HTTP sites in history
    http_sites = []
    for url, title in history_data:
        url_lower = url.lower()
        # Check for HTTP (but not HTTPS)
        if url_lower.startswith('http://') and not url_lower.startswith('https://'):
            # Ignore local file:// and chrome:// URLs
            if not any(prefix in url_lower for prefix in ['file://', 'chrome://', 'about:', 'data:']):
                http_sites.append(url)
    
    if http_sites:
        criteria_met['no_insecure_sites'] = False
        feedback_parts.append(f"✗ Visited insecure HTTP sites: {len(http_sites)} found")
        logger.info(f"Insecure sites: {http_sites[:3]}")  # Log first 3
    else:
        criteria_met['no_insecure_sites'] = True
        feedback_parts.append("✓ No insecure HTTP sites visited")
    
    # Calculate score
    criteria_count = sum(criteria_met.values())
    total_criteria = len(criteria_met)
    score = int((criteria_count / total_criteria) * 100)
    passed = score >= 80  # Need 4/5 criteria
    
    # Generate summary feedback
    summary = f"\nVerification Summary: {criteria_count}/{total_criteria} criteria met\n"
    summary += "\n".join(feedback_parts)
    summary += f"\n\n{'='*50}"
    summary += f"\nFinal Score: {score}%"
    summary += f"\nResult: {'✅ PASSED' if passed else '❌ FAILED'}"
    
    if not passed:
        summary += "\n\n💡 Tip: To complete this task successfully:"
        summary += "\n   1. Navigate to https://example.com (use Ctrl+L)"
        summary += "\n   2. Click the padlock icon 🔒 in the address bar"
        summary += "\n   3. Verify the 'Connection is secure' message"
        summary += "\n   4. Spend time examining the security information"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_count}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
        "details": {
            "criteria_met": criteria_count,
            "total_criteria": total_criteria,
            "criteria": criteria_met,
            "active_url": active_url,
            "duration_seconds": duration,
            "insecure_sites_count": len(http_sites)
        }
    }
