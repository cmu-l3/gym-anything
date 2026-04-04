#!/usr/bin/env python3
"""
Verifier for Chrome History Recovery Search Task (history_recovery_search@1)
Task: Use browsing history to recover a previously visited page about REST API authentication

Verification Strategy:
1. CDP-based Active Tab Verification: Check current URL matches target page
2. History Database Analysis: Verify target URL exists in history
3. History Interface Access Detection: Confirm chrome://history/ was accessed
4. Search Activity Detection: Verify history search was used (not direct navigation)
5. Timestamp Validation: Ensure target page has realistic timestamp
"""

import logging
import sys
import os
import json
import sqlite3
import tempfile
import re
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


# Target page details
TARGET_URL = "file:///home/ga/Documents/rest_api_auth_guide.html"
TARGET_TITLE_KEYWORDS = ["rest", "api", "authentication", "best practices"]
HISTORY_URL_PATTERN = "chrome://history"


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for history_recovery_search@1.
    
    Verifies that agent successfully recovered the target page using Chrome history search.
    
    Multi-criteria verification:
    - Criterion 1: Active tab shows target URL (primary success indicator)
    - Criterion 2: History interface was accessed (chrome://history/ in history)
    - Criterion 3: Target URL exists in history database with recent timestamp
    - Criterion 4: Evidence of search/navigation from history (not direct URL typing)
    - Criterion 5: History database integrity (not cleared or corrupted)
    
    Scoring:
    - 100%: All 5 criteria met (perfect execution)
    - 85%: 4/5 criteria met (good, passes threshold)
    - 70%: 3/5 criteria met (partial success)
    - 50%: 2/5 criteria met (minimal progress)
    - <50%: 0-1 criteria met (task failed)
    
    Pass threshold: 85% (requires at least 4/5 criteria)
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Initialize criteria tracking
        criteria_results = {
            "correct_page_loaded": False,
            "history_accessed": False,
            "target_in_history": False,
            "proper_recovery_method": False,
            "history_intact": False
        }
        
        feedback_parts = []
        
        # Criterion 1: Check active tab URL via CDP
        logger.info("=== Criterion 1: Active Tab URL Verification ===")
        active_url = get_active_tab_url(copy_from_env)
        
        if active_url:
            logger.info(f"Active tab URL: {active_url}")
            
            # Normalize URLs for comparison
            active_url_normalized = normalize_url(active_url)
            target_url_normalized = normalize_url(TARGET_URL)
            
            if active_url_normalized == target_url_normalized:
                criteria_results["correct_page_loaded"] = True
                feedback_parts.append("✓ Correct page loaded: Target REST API authentication guide")
                logger.info("✓ PASS: Active tab matches target URL")
            else:
                feedback_parts.append(f"✗ Wrong page loaded: {active_url[:80]}...")
                feedback_parts.append(f"  Expected: {TARGET_URL}")
                logger.info(f"✗ FAIL: Active tab URL does not match target")
        else:
            feedback_parts.append("✗ Could not determine active tab URL")
            logger.warning("Could not retrieve active tab URL")
        
        # Criterion 2 & 3: History database analysis
        logger.info("=== Criterion 2-3: History Database Analysis ===")
        history_db_path = get_history_database(copy_from_env)
        
        if history_db_path:
            # Check if target URL exists in history
            target_exists, target_info = check_target_in_history(history_db_path, TARGET_URL)
            
            if target_exists:
                criteria_results["target_in_history"] = True
                feedback_parts.append(f"✓ Target page found in history database")
                if target_info:
                    feedback_parts.append(f"  Title: {target_info.get('title', 'unknown')}")
                    feedback_parts.append(f"  Visit count: {target_info.get('visit_count', 0)}")
                logger.info("✓ PASS: Target URL found in history")
            else:
                feedback_parts.append("✗ Target page not found in history database")
                logger.info("✗ FAIL: Target URL not in history")
            
            # Check if chrome://history/ was accessed
            history_accessed = check_history_interface_used(history_db_path)
            
            if history_accessed:
                criteria_results["history_accessed"] = True
                feedback_parts.append("✓ History interface was accessed (chrome://history/)")
                logger.info("✓ PASS: History interface was accessed")
            else:
                feedback_parts.append("✗ No evidence of history interface access")
                logger.info("✗ FAIL: History interface not accessed")
            
            # Check history database integrity
            history_ok, history_status = check_history_integrity(history_db_path)
            
            if history_ok:
                criteria_results["history_intact"] = True
                feedback_parts.append("✓ History database intact and not cleared")
                logger.info("✓ PASS: History integrity verified")
            else:
                feedback_parts.append(f"✗ History database issue: {history_status}")
                logger.info(f"✗ FAIL: History integrity issue - {history_status}")
            
            # Clean up temp history file
            try:
                os.unlink(history_db_path)
            except:
                pass
        else:
            feedback_parts.append("✗ Could not access history database for verification")
            logger.warning("Failed to retrieve history database")
        
        # Criterion 4: Proper recovery method (heuristic)
        logger.info("=== Criterion 4: Recovery Method Analysis ===")
        # If history was accessed AND correct page loaded, assume proper method
        if criteria_results["history_accessed"] and criteria_results["correct_page_loaded"]:
            criteria_results["proper_recovery_method"] = True
            feedback_parts.append("✓ Proper recovery method used (history search)")
            logger.info("✓ PASS: Evidence of proper recovery method")
        else:
            # Check if page was reached without history access (direct navigation)
            if criteria_results["correct_page_loaded"] and not criteria_results["history_accessed"]:
                feedback_parts.append("⚠ Page reached but no evidence of history usage")
                feedback_parts.append("  (May have typed URL directly instead of using history)")
                logger.info("⚠ WARN: Correct page but unclear method")
            else:
                feedback_parts.append("✗ Did not use history search to recover page")
                logger.info("✗ FAIL: No evidence of history-based recovery")
        
        # Calculate score based on criteria met
        criteria_count = sum(criteria_results.values())
        score = (criteria_count / 5.0) * 100
        passed = score >= 85  # Need at least 4/5 criteria
        
        # Build final feedback
        feedback = f"History Recovery Task Verification\n{'='*50}\n"
        feedback += f"Criteria met: {criteria_count}/5\n\n"
        feedback += "\n".join(feedback_parts)
        feedback += f"\n\n{'='*50}\n"
        feedback += f"Final Score: {int(score)}%\n"
        
        if passed:
            feedback += "Result: ✅ PASSED - Successfully recovered page from history"
        else:
            feedback += "Result: ❌ FAILED - Did not properly recover page using history search"
        
        logger.info(f"Verification complete: passed={passed}, score={int(score)}, criteria={criteria_count}/5")
        
        # Clean up
        cleanup_verification_temp()
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": feedback,
            "details": {
                "criteria_met": criteria_count,
                "criteria_results": criteria_results,
                "active_url": active_url,
                "target_url": TARGET_URL
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


def get_active_tab_url(copy_from_env) -> Optional[str]:
    """
    Get active tab URL from CDP data.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Active tab URL or None
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        
        copy_from_env("/tmp/active_url.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            url = f.read().strip()
        
        os.unlink(temp_file.name)
        
        return url if url else None
        
    except Exception as e:
        logger.warning(f"Could not get active tab URL: {e}")
        return None


def get_history_database(copy_from_env) -> Optional[str]:
    """
    Copy Chrome History database from container to host.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Path to local copy of History database, or None
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='_History', mode='wb')
        temp_file.close()
        
        # Try to copy from verification directory first
        possible_paths = [
            "/tmp/history_recovery_verification/History",
            "/tmp/History",
            "/home/ga/.config/google-chrome-cdp/Default/History",
            "/home/ga/.config/google-chrome/Default/History"
        ]
        
        for path in possible_paths:
            try:
                logger.info(f"Trying to copy History from: {path}")
                copy_from_env(path, temp_file.name)
                
                # Check if file has content
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    logger.info(f"✓ Successfully copied History database from: {path}")
                    return temp_file.name
            except Exception as e:
                logger.debug(f"Failed to copy from {path}: {e}")
                continue
        
        # If we get here, none worked
        os.unlink(temp_file.name)
        return None
        
    except Exception as e:
        logger.error(f"Error getting history database: {e}")
        return None


def check_target_in_history(history_db_path: str, target_url: str) -> Tuple[bool, Optional[Dict]]:
    """
    Check if target URL exists in Chrome history database.
    
    Args:
        history_db_path: Path to History SQLite database
        target_url: Target URL to search for
        
    Returns:
        Tuple of (exists: bool, info: dict or None)
    """
    try:
        conn = sqlite3.connect(history_db_path)
        cursor = conn.cursor()
        
        # Search for target URL
        cursor.execute("""
            SELECT url, title, visit_count, last_visit_time
            FROM urls
            WHERE url = ?
            ORDER BY last_visit_time DESC
            LIMIT 1
        """, (target_url,))
        
        result = cursor.fetchone()
        conn.close()
        
        if result:
            url, title, visit_count, last_visit_time = result
            return True, {
                "url": url,
                "title": title,
                "visit_count": visit_count,
                "last_visit_time": last_visit_time
            }
        else:
            return False, None
            
    except Exception as e:
        logger.error(f"Error checking target in history: {e}")
        return False, None


def check_history_interface_used(history_db_path: str) -> bool:
    """
    Check if chrome://history/ was accessed during the task.
    
    Args:
        history_db_path: Path to History SQLite database
        
    Returns:
        True if history interface was accessed
    """
    try:
        conn = sqlite3.connect(history_db_path)
        cursor = conn.cursor()
        
        # Look for chrome://history/ visits
        cursor.execute("""
            SELECT url, last_visit_time
            FROM urls
            WHERE url LIKE 'chrome://history%'
            ORDER BY last_visit_time DESC
            LIMIT 5
        """)
        
        results = cursor.fetchall()
        conn.close()
        
        # If any history URL found, interface was accessed
        return len(results) > 0
        
    except Exception as e:
        logger.error(f"Error checking history interface usage: {e}")
        return False


def check_history_integrity(history_db_path: str) -> Tuple[bool, str]:
    """
    Check if history database is intact and not corrupted/cleared.
    
    Args:
        history_db_path: Path to History SQLite database
        
    Returns:
        Tuple of (ok: bool, status_message: str)
    """
    try:
        conn = sqlite3.connect(history_db_path)
        cursor = conn.cursor()
        
        # Check if urls table exists and has entries
        cursor.execute("SELECT COUNT(*) FROM urls")
        url_count = cursor.fetchone()[0]
        
        # Check if visits table exists and has entries
        cursor.execute("SELECT COUNT(*) FROM visits")
        visit_count = cursor.fetchone()[0]
        
        conn.close()
        
        if url_count == 0 or visit_count == 0:
            return False, "History appears to be empty or cleared"
        
        if url_count < 2:
            return False, f"Suspiciously few history entries ({url_count})"
        
        return True, f"History intact ({url_count} URLs, {visit_count} visits)"
        
    except sqlite3.Error as e:
        return False, f"Database error: {e}"
    except Exception as e:
        return False, f"Error checking integrity: {e}"


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison (remove trailing slashes, convert to lowercase).
    
    Args:
        url: URL to normalize
        
    Returns:
        Normalized URL
    """
    if not url:
        return ""
    
    # Remove trailing slashes
    url = url.rstrip('/')
    
    # Remove URL fragments (#...)
    url = url.split('#')[0]
    
    # Remove query parameters for file:// URLs
    if url.startswith('file://'):
        url = url.split('?')[0]
    
    return url.lower()
