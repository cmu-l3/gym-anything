#!/usr/bin/env python3
"""
Verifier for Chrome History Search and Recovery Task (history_search_recovery@1)
Task: Use history search to find and navigate to previously visited renewable energy page

Verification Strategy:
- Check active tab URL matches target URL
- Verify target URL exists in history database
- Confirm visit count is >= 2 (original seeded visit + recovery visit)
- Validate that navigation occurred (not just stayed on starting page)
"""

import logging
import sys
import os
import json
import sqlite3
import tempfile
from pathlib import Path
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
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


def verify_task(traj, env_info, task_info):
    """
    Main verification function for history_search_recovery@1.
    
    Verifies:
    1. Active tab URL matches target URL
    2. Target URL exists in history database
    3. Visit count is >= 2 (proves re-visit occurred)
    4. Navigation actually occurred (not stuck on starting page)
    
    Scoring:
    - 100%: All 4 criteria met (perfect recovery)
    - 75%: 3/4 criteria met (good, passing)
    - 50%: 2/4 criteria met (partial, failing)
    - 25%: 1/4 criteria met (minimal, failing)
    - 0%: 0 criteria met (complete failure)
    
    Pass threshold: 75% (requires at least 3 out of 4 criteria)
    
    Args:
        traj: Trajectory data (could be used for behavioral analysis)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }
    
    # Target URL that should be recovered
    TARGET_URL = "https://example.com/energy-stats/renewable-2024"
    
    try:
        # Criterion 1: Check active tab URL
        active_url, url_error = get_active_tab_url(copy_from_env)
        
        if active_url is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not retrieve active tab URL: {url_error}"
            }
        
        url_matches = normalize_url(active_url) == normalize_url(TARGET_URL)
        logger.info(f"✓ Active URL check: {active_url} {'MATCHES' if url_matches else 'DOES NOT MATCH'} target")
        
        # Criterion 2 & 3: Check history database
        history_data, history_error = get_history_data(copy_from_env, TARGET_URL)
        
        if history_data is None:
            logger.warning(f"Could not retrieve history data: {history_error}")
            target_in_history = False
            visit_count = 0
        else:
            target_in_history = history_data['exists']
            visit_count = history_data['visit_count']
            logger.info(f"✓ History check: Target {'EXISTS' if target_in_history else 'NOT FOUND'} in history")
            logger.info(f"✓ Visit count: {visit_count} visits")
        
        revisit_occurred = visit_count >= 2
        
        # Criterion 4: Navigation occurred (not stuck on starting page)
        starting_urls = ["https://www.google.com", "https://google.com", "about:blank"]
        navigation_occurred = not any(normalize_url(active_url).startswith(normalize_url(start)) 
                                      for start in starting_urls)
        logger.info(f"✓ Navigation check: {'USER NAVIGATED' if navigation_occurred else 'STUCK ON START PAGE'}")
        
        # Calculate score based on criteria
        criteria_results = [
            url_matches,
            target_in_history,
            revisit_occurred,
            navigation_occurred
        ]
        
        criteria_met = sum(criteria_results)
        score = (criteria_met / 4.0) * 100
        passed = score >= 75
        
        # Generate detailed feedback
        feedback_parts = []
        feedback_parts.append(f"Verification Results: {criteria_met}/4 criteria met")
        feedback_parts.append(f"")
        feedback_parts.append(f"1. Active URL matches target: {'✓' if url_matches else '✗'}")
        feedback_parts.append(f"   Active: {active_url}")
        feedback_parts.append(f"   Target: {TARGET_URL}")
        feedback_parts.append(f"")
        feedback_parts.append(f"2. Target exists in history: {'✓' if target_in_history else '✗'}")
        feedback_parts.append(f"")
        feedback_parts.append(f"3. Re-visit occurred (visit count >= 2): {'✓' if revisit_occurred else '✗'}")
        feedback_parts.append(f"   Visit count: {visit_count}")
        feedback_parts.append(f"")
        feedback_parts.append(f"4. Navigation occurred: {'✓' if navigation_occurred else '✗'}")
        feedback_parts.append(f"")
        
        if passed:
            feedback_parts.append("✅ Task completed successfully!")
            feedback_parts.append("Agent successfully used history search to recover the target URL.")
        else:
            feedback_parts.append("❌ Task incomplete or failed")
            if not url_matches:
                feedback_parts.append("- Agent did not navigate to the correct target URL")
            if not target_in_history:
                feedback_parts.append("- Target URL not found in browser history")
            if not revisit_occurred:
                feedback_parts.append("- No evidence of re-visiting the target page")
            if not navigation_occurred:
                feedback_parts.append("- Agent did not navigate away from starting page")
        
        feedback = "\n".join(feedback_parts)
        
        # Clean up
        cleanup_verification_temp()
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": feedback,
            "details": {
                "active_url": active_url,
                "target_url": TARGET_URL,
                "url_matches": url_matches,
                "target_in_history": target_in_history,
                "visit_count": visit_count,
                "revisit_occurred": revisit_occurred,
                "navigation_occurred": navigation_occurred
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


def get_active_tab_url(copy_from_env):
    """
    Get the active tab URL from the exported data.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (url: str or None, error_message: str)
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try to copy the final URL file
        copy_from_env("/tmp/final_active_url.txt", temp_path)
        
        with open(temp_path, 'r') as f:
            url = f.read().strip()
        
        if not url:
            return None, "Active URL is empty"
        
        return url, ""
        
    except Exception as e:
        return None, f"Failed to retrieve active URL: {e}"
    finally:
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def get_history_data(copy_from_env, target_url):
    """
    Get history data for the target URL from Chrome's history database.
    
    Args:
        copy_from_env: Function to copy files from container
        target_url: URL to check in history
        
    Returns:
        Tuple of (dict with 'exists' and 'visit_count', error_message)
    """
    temp_db = None
    try:
        # Copy history database from container
        temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_db_path = temp_db.name
        temp_db.close()
        
        copy_from_env("/tmp/chrome_history_export.db", temp_db_path)
        
        # Check if file was copied successfully
        if not os.path.exists(temp_db_path) or os.path.getsize(temp_db_path) == 0:
            return None, "History database is empty or not found"
        
        # Query the database
        conn = sqlite3.connect(temp_db_path)
        cursor = conn.cursor()
        
        # Check if URL exists and get visit count
        cursor.execute("""
            SELECT id, url, visit_count, last_visit_time 
            FROM urls 
            WHERE url = ?
        """, (target_url,))
        
        result = cursor.fetchone()
        
        if result:
            url_id, url, visit_count, last_visit_time = result
            
            # Also check visits table for more accurate count
            cursor.execute("""
                SELECT COUNT(*) 
                FROM visits 
                WHERE url = ?
            """, (url_id,))
            
            visits_table_count = cursor.fetchone()[0]
            
            # Use the maximum of the two counts
            actual_visit_count = max(visit_count, visits_table_count)
            
            conn.close()
            
            logger.info(f"Target URL found in history:")
            logger.info(f"  URL: {url}")
            logger.info(f"  Visit count (urls table): {visit_count}")
            logger.info(f"  Visit count (visits table): {visits_table_count}")
            logger.info(f"  Actual visit count: {actual_visit_count}")
            
            return {
                'exists': True,
                'visit_count': actual_visit_count,
                'last_visit_time': last_visit_time
            }, ""
        else:
            conn.close()
            logger.info(f"Target URL NOT found in history database")
            return {
                'exists': False,
                'visit_count': 0,
                'last_visit_time': None
            }, ""
        
    except sqlite3.Error as e:
        return None, f"SQLite error: {e}"
    except Exception as e:
        return None, f"Error querying history: {e}"
    finally:
        if temp_db and os.path.exists(temp_db_path):
            try:
                os.unlink(temp_db_path)
            except:
                pass


def normalize_url(url):
    """
    Normalize URL for comparison (remove trailing slashes, convert to lowercase).
    
    Args:
        url: URL string to normalize
        
    Returns:
        Normalized URL string
    """
    if not url:
        return ""
    
    # Remove trailing slashes
    url = url.rstrip('/')
    
    # Convert to lowercase for case-insensitive comparison
    url = url.lower()
    
    # Remove common variations
    url = url.replace('http://', '').replace('https://', '')
    
    return url
