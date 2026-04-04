#!/usr/bin/env python3
"""
Verifier for Chrome Clear Browsing History Task (clear_browsing_history@1)
Task: Clear all browsing history while preserving cookies and other data types

Verification Strategy:
- Copy Chrome History database from container
- Parse SQLite database to count remaining URLs
- Check that baseline URLs from setup are removed
- Verify history is empty or nearly empty (≥90% reduction)
- Verify Cookies database was NOT cleared (preservation check)
- Multi-criteria scoring with detailed feedback
"""

import logging
import sys
import os
import sqlite3
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import (
        cleanup_verification_temp,
        parse_history,
        parse_cookies
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def copy_file_from_container(copy_from_env, container_paths: List[str], suffix: str) -> Tuple[bool, str, str]:
    """
    Try to copy a file from multiple possible container paths.
    
    Args:
        copy_from_env: Function to copy files from container
        container_paths: List of possible paths to try
        suffix: File suffix for temp file
        
    Returns:
        Tuple of (success, local_path, error_message)
    """
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    temp_path = temp_file.name
    temp_file.close()
    
    for container_path in container_paths:
        try:
            logger.info(f"Trying to copy from: {container_path}")
            copy_from_env(container_path, temp_path)
            
            # Check if file has content
            if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                logger.info(f"✓ Successfully copied from: {container_path}")
                return True, temp_path, ""
        except Exception as e:
            logger.debug(f"Could not copy from {container_path}: {e}")
            continue
    
    # Cleanup temp file if all attempts failed
    if os.path.exists(temp_path):
        os.unlink(temp_path)
    
    return False, "", f"Could not copy file from any of {len(container_paths)} attempted paths"


def get_baseline_urls(copy_from_env) -> List[str]:
    """
    Get baseline URLs that were visited during setup.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        List of baseline URLs
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, mode='w+', suffix='.txt')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/baseline_urls_export.txt", temp_path)
        
        with open(temp_path, 'r') as f:
            urls = [line.strip() for line in f if line.strip()]
        
        os.unlink(temp_path)
        
        logger.info(f"Loaded {len(urls)} baseline URLs")
        return urls
        
    except Exception as e:
        logger.warning(f"Could not load baseline URLs: {e}")
        # Return default baseline URLs if file not available
        return [
            "https://www.wikipedia.org",
            "https://news.ycombinator.com",
            "https://github.com",
            "https://stackoverflow.com",
            "https://www.reddit.com",
            "https://www.python.org",
            "https://developer.mozilla.org"
        ]


def count_history_entries(history_db_path: str) -> int:
    """
    Count total number of URLs in History database.
    
    Args:
        history_db_path: Path to History SQLite database
        
    Returns:
        Number of URL entries
    """
    try:
        conn = sqlite3.connect(history_db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM urls")
        count = cursor.fetchone()[0]
        conn.close()
        
        logger.info(f"History database contains {count} URLs")
        return count
        
    except Exception as e:
        logger.error(f"Error counting history entries: {e}")
        return -1


def check_baseline_urls_removed(history_db_path: str, baseline_urls: List[str]) -> Tuple[int, List[str]]:
    """
    Check how many baseline URLs are still present in history.
    
    Args:
        history_db_path: Path to History SQLite database
        baseline_urls: List of URLs that should be removed
        
    Returns:
        Tuple of (number_remaining, list_of_remaining_urls)
    """
    try:
        conn = sqlite3.connect(history_db_path)
        cursor = conn.cursor()
        
        remaining = []
        for url in baseline_urls:
            # Check if URL or domain is still in history
            domain = url.replace('https://', '').replace('http://', '').split('/')[0]
            
            cursor.execute("SELECT url FROM urls WHERE url LIKE ? OR url LIKE ?", 
                         (f'%{domain}%', f'%{url}%'))
            results = cursor.fetchall()
            
            if results:
                remaining.append(url)
                logger.debug(f"Baseline URL still present: {url}")
        
        conn.close()
        
        logger.info(f"{len(remaining)} out of {len(baseline_urls)} baseline URLs still present")
        return len(remaining), remaining
        
    except Exception as e:
        logger.error(f"Error checking baseline URLs: {e}")
        return -1, []


def count_cookies(cookies_db_path: str) -> int:
    """
    Count total number of cookies (to verify they were preserved).
    
    Args:
        cookies_db_path: Path to Cookies SQLite database
        
    Returns:
        Number of cookie entries
    """
    try:
        conn = sqlite3.connect(cookies_db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM cookies")
        count = cursor.fetchone()[0]
        conn.close()
        
        logger.info(f"Cookies database contains {count} cookies")
        return count
        
    except Exception as e:
        logger.error(f"Error counting cookies: {e}")
        return -1


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for clear_browsing_history@1 task.
    
    Verifies:
    1. History database has very few entries (≤2 URLs)
    2. Baseline URLs from setup are removed (0 remaining)
    3. History was significantly reduced (≥90% reduction from baseline)
    4. Cookies database was NOT cleared (has entries)
    
    Scoring:
    - 100%: All 4 criteria met (perfect execution)
    - 85-99%: 3/4 criteria met (minor issue)
    - 70-84%: 3/4 criteria met with some tolerance
    - 50-69%: 2/4 criteria met (partial success)
    - <50%: <2 criteria met (task failed)
    
    Pass threshold: 70% (requires at least 3 out of 4 criteria or excellent performance on key metrics)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    try:
        # Get baseline URLs
        baseline_urls = get_baseline_urls(copy_from_env)
        baseline_count = len(baseline_urls)
        
        # Criterion 1 & 2 & 3: Check History database
        logger.info("Checking History database...")
        
        history_paths = [
            "/tmp/history_export.db",
            "/home/ga/.config/google-chrome-cdp/Default/History",
            "/home/ga/.config/google-chrome/Default/History"
        ]
        
        success, history_db_path, error = copy_file_from_container(
            copy_from_env, history_paths, '.db'
        )
        
        if not success:
            feedback_parts.append(f"✗ Could not access History database: {error}")
            return {
                "passed": False,
                "score": 0,
                "feedback": "\n".join(feedback_parts)
            }
        
        # Count remaining history entries
        history_count = count_history_entries(history_db_path)
        
        if history_count < 0:
            feedback_parts.append("✗ Failed to query History database")
            os.unlink(history_db_path)
            return {
                "passed": False,
                "score": 0,
                "feedback": "\n".join(feedback_parts)
            }
        
        # Criterion 1: History is empty or nearly empty
        if history_count == 0:
            feedback_parts.append("✓ History completely cleared (0 entries)")
            criteria_met += 1
        elif history_count <= 2:
            feedback_parts.append(f"✓ History mostly cleared ({history_count} entries remaining)")
            criteria_met += 1
        elif history_count <= 5:
            feedback_parts.append(f"⚠ History partially cleared ({history_count} entries remaining, expected ≤2)")
            criteria_met += 0.5
        else:
            feedback_parts.append(f"✗ History not sufficiently cleared ({history_count} entries remaining)")
        
        # Criterion 2: Baseline URLs removed
        baseline_remaining, remaining_urls = check_baseline_urls_removed(history_db_path, baseline_urls)
        
        if baseline_remaining < 0:
            feedback_parts.append("⚠ Could not verify baseline URL removal")
        elif baseline_remaining == 0:
            feedback_parts.append(f"✓ All {baseline_count} baseline URLs removed")
            criteria_met += 1
        elif baseline_remaining <= 2:
            feedback_parts.append(f"⚠ Most baseline URLs removed ({baseline_remaining}/{baseline_count} remaining)")
            criteria_met += 0.5
        else:
            feedback_parts.append(f"✗ Baseline URLs not removed ({baseline_remaining}/{baseline_count} still present)")
            if remaining_urls:
                feedback_parts.append(f"  Still present: {', '.join(remaining_urls[:3])}")
        
        # Criterion 3: Significant reduction (≥90%)
        # Baseline should have at least 7 URLs from setup
        expected_baseline = max(baseline_count, 7)
        reduction_percentage = ((expected_baseline - history_count) / expected_baseline) * 100
        
        if reduction_percentage >= 90:
            feedback_parts.append(f"✓ History reduced by {reduction_percentage:.1f}% (≥90% reduction achieved)")
            criteria_met += 1
        elif reduction_percentage >= 70:
            feedback_parts.append(f"⚠ History reduced by {reduction_percentage:.1f}% (expected ≥90%)")
            criteria_met += 0.5
        else:
            feedback_parts.append(f"✗ Insufficient history reduction ({reduction_percentage:.1f}%, expected ≥90%)")
        
        # Clean up history database
        os.unlink(history_db_path)
        
        # Criterion 4: Cookies preserved
        logger.info("Checking Cookies database (should be preserved)...")
        
        cookies_paths = [
            "/tmp/cookies_export.db",
            "/home/ga/.config/google-chrome-cdp/Default/Cookies",
            "/home/ga/.config/google-chrome/Default/Cookies"
        ]
        
        success, cookies_db_path, error = copy_file_from_container(
            copy_from_env, cookies_paths, '.db'
        )
        
        if not success:
            feedback_parts.append(f"⚠ Could not access Cookies database: {error}")
            # Don't fail completely, but don't award points
        else:
            cookie_count = count_cookies(cookies_db_path)
            os.unlink(cookies_db_path)
            
            if cookie_count < 0:
                feedback_parts.append("⚠ Could not query Cookies database")
            elif cookie_count > 0:
                feedback_parts.append(f"✓ Cookies preserved ({cookie_count} cookies still present)")
                criteria_met += 1
            else:
                feedback_parts.append("✗ Cookies were cleared (should have been preserved)")
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 70
        
        # Add summary
        feedback_parts.append(f"\n{'='*50}")
        feedback_parts.append(f"Criteria met: {criteria_met:.1f}/{total_criteria}")
        feedback_parts.append(f"Final score: {score}%")
        feedback_parts.append(f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}")
        
        if passed:
            feedback_parts.append("\n✅ Browsing history successfully cleared!")
        else:
            feedback_parts.append("\n❌ History clearing incomplete or incorrect")
            feedback_parts.append("Ensure you:")
            feedback_parts.append("  1. Selected 'All time' as the time range")
            feedback_parts.append("  2. Checked ONLY 'Browsing history'")
            feedback_parts.append("  3. Unchecked cookies, cache, and other data types")
            feedback_parts.append("  4. Clicked 'Clear data' button")
        
        feedback = "\n".join(feedback_parts)
        
        logger.info(f"Verification complete: passed={passed}, score={score}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "history_count": history_count,
                "baseline_urls_total": baseline_count,
                "baseline_urls_remaining": baseline_remaining,
                "reduction_percentage": reduction_percentage,
                "criteria_met": criteria_met
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
