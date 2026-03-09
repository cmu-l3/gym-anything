#!/usr/bin/env python3
"""
Verifier for Chrome Site-Specific Cookie Deletion Task (clear_site_cookies@1)
Task: Delete all cookies for httpbin.org while preserving cookies from other sites

Verification Strategy:
- Copy Chrome Cookies SQLite database from container
- Query cookies table for target domain (httpbin.org)
- Query cookies table for control domains (example.com, google.com, etc.)
- Verify target domain has 0 cookies
- Verify control domains still have cookies
- Verify total cookies > 0 (proving selective deletion)
- Calculate score based on 4 criteria
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for clear_site_cookies@1 task.
    
    Verifies that:
    1. Target domain (httpbin.org) has 0 cookies
    2. Control domains still have cookies
    3. Total cookies > 0 (selective deletion)
    4. Database is accessible
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str), and 'details' (dict)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get Cookies database from container
        cookies_db_path, error_msg = get_cookies_database(copy_from_env)
        
        if cookies_db_path is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Cookies database: {error_msg}"
            }
        
        # Perform verification
        result = verify_selective_cookie_deletion(
            cookies_db_path,
            target_domain="httpbin.org",
            control_domains=["example.com", "google.com", "gstatic.com", "wikipedia.org"]
        )
        
        # Clean up temporary files
        try:
            if cookies_db_path and os.path.exists(cookies_db_path):
                os.unlink(cookies_db_path)
        except Exception as e:
            logger.warning(f"Failed to clean up temp file: {e}")
        
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


def get_cookies_database(copy_from_env) -> Tuple[Optional[str], str]:
    """
    Copy Cookies SQLite database from container to host.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (local_path: str or None, error_message: str)
    """
    try:
        # Create temporary file for the database
        temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_path = temp_db.name
        temp_db.close()
        
        # Try multiple possible locations for the Cookies database
        possible_paths = [
            "/tmp/chrome_cookies.db",  # Exported by export_result.sh
            "/home/ga/.config/google-chrome-cdp/Default/Cookies",
            "/home/ga/.config/google-chrome/Default/Cookies",
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Attempting to copy Cookies database from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Verify file was copied and has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    logger.info(f"✓ Successfully copied Cookies database from: {container_path}")
                    return temp_path, ""
                else:
                    logger.debug(f"File copied but empty: {container_path}")
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        
        return None, "Cookies database not found in any known location"
        
    except Exception as e:
        logger.error(f"Error getting Cookies database: {e}")
        return None, f"Error accessing Cookies database: {str(e)}"


def verify_selective_cookie_deletion(
    cookies_db_path: str,
    target_domain: str = "httpbin.org",
    control_domains: List[str] = None
) -> Dict[str, Any]:
    """
    Verify selective cookie deletion was performed correctly.
    
    Checks:
    1. Target domain has 0 cookies
    2. At least one control domain has cookies
    3. Total cookies > 0 (not all deleted)
    4. Database is valid and accessible
    
    Args:
        cookies_db_path: Path to Chrome Cookies SQLite database
        target_domain: Domain that should have no cookies
        control_domains: List of domains that should still have cookies
        
    Returns:
        Dict with verification results
    """
    if control_domains is None:
        control_domains = ["example.com", "google.com", "gstatic.com", "wikipedia.org"]
    
    try:
        # Connect to SQLite database
        conn = sqlite3.connect(cookies_db_path)
        cursor = conn.cursor()
        
        # Verify table exists
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cookies';")
        if not cursor.fetchone():
            conn.close()
            return {
                "passed": False,
                "score": 0,
                "feedback": "Cookies database is invalid (no 'cookies' table)",
                "details": {}
            }
        
        # Criterion 1: Check target domain cookies (should be 0)
        cursor.execute(
            "SELECT COUNT(*) FROM cookies WHERE host_key LIKE ?",
            (f"%{target_domain}%",)
        )
        target_count = cursor.fetchone()[0]
        target_deleted = (target_count == 0)
        
        logger.info(f"Target domain ({target_domain}) cookie count: {target_count}")
        
        # Criterion 2: Check control domain cookies (at least one should have cookies)
        control_counts = {}
        for domain in control_domains:
            cursor.execute(
                "SELECT COUNT(*) FROM cookies WHERE host_key LIKE ?",
                (f"%{domain}%",)
            )
            count = cursor.fetchone()[0]
            control_counts[domain] = count
            logger.info(f"Control domain ({domain}) cookie count: {count}")
        
        controls_preserved = any(count > 0 for count in control_counts.values())
        
        # Criterion 3: Check total cookies (should be > 0 for selective deletion)
        cursor.execute("SELECT COUNT(*) FROM cookies")
        total_count = cursor.fetchone()[0]
        selective_deletion = (total_count > 0)
        
        logger.info(f"Total cookie count: {total_count}")
        
        # Get list of remaining domains for detailed feedback
        cursor.execute("SELECT DISTINCT host_key FROM cookies LIMIT 10")
        remaining_domains = [row[0] for row in cursor.fetchall()]
        
        conn.close()
        
        # Criterion 4: Database accessible (we got this far, so yes)
        database_accessible = True
        
        # Calculate score based on criteria met
        criteria = [
            target_deleted,
            controls_preserved,
            selective_deletion,
            database_accessible
        ]
        criteria_met = sum(criteria)
        score = int((criteria_met / 4.0) * 100)
        passed = score >= 75  # Need at least 3/4 criteria (75%)
        
        # Generate detailed feedback
        feedback_parts = []
        feedback_parts.append(f"Verification Results: {criteria_met}/4 criteria met")
        feedback_parts.append("")
        
        if target_deleted:
            feedback_parts.append(f"✓ Target domain ({target_domain}) cookies deleted (0 cookies)")
        else:
            feedback_parts.append(f"✗ Target domain still has {target_count} cookie(s) - deletion failed")
        
        if controls_preserved:
            preserved = [f"{d}({c})" for d, c in control_counts.items() if c > 0]
            feedback_parts.append(f"✓ Control domains preserved: {', '.join(preserved)}")
        else:
            feedback_parts.append(f"✗ No control domain cookies found - may have deleted ALL cookies")
        
        if selective_deletion:
            feedback_parts.append(f"✓ Selective deletion confirmed ({total_count} total cookies remain)")
        else:
            feedback_parts.append(f"✗ All cookies deleted - not selective (0 cookies remain)")
        
        if database_accessible:
            feedback_parts.append(f"✓ Database accessible and valid")
        
        feedback_parts.append("")
        feedback_parts.append(f"Remaining domains (sample): {remaining_domains[:5]}")
        
        if passed:
            feedback_parts.append("")
            feedback_parts.append("✅ Task completed successfully - selective cookie deletion verified!")
        else:
            feedback_parts.append("")
            feedback_parts.append("❌ Task incomplete - cookies not selectively deleted")
        
        feedback = "\n".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "target_count": target_count,
                "control_counts": control_counts,
                "total_cookies": total_count,
                "criteria_met": criteria_met,
                "remaining_domains": remaining_domains
            }
        }
        
    except sqlite3.Error as e:
        logger.error(f"SQLite error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Database error: {e}",
            "details": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed: {e}",
            "details": {}
        }
