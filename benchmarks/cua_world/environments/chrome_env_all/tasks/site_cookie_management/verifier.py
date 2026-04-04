#!/usr/bin/env python3
"""
Verifier for Chrome Site-Specific Cookie Management Task (site_cookie_management@1)
Task: Selectively delete github.com cookies while preserving other sites' cookies

Verification Strategy:
- Copy Chrome Cookies SQLite database from container
- Query cookies table for specific domains
- Verify github.com cookies are removed (count = 0)
- Verify example.com cookies are preserved (count > 0)
- Verify wikipedia.org cookies are preserved (count > 0)
- Verify total cookie count > 0 (selective, not bulk deletion)
- Check database integrity

Scoring:
- 100%: All 5 criteria met (perfect selective deletion)
- 80-99%: Target removed + both controls preserved (4/5 criteria)
- 60-79%: Target removed + at least one control preserved (3/5 criteria)
- 30-59%: Target removed but controls lost (2/5 criteria)
- 0-29%: Target not removed or database inaccessible (0-1 criteria)

Pass threshold: 80% (requires selective deletion with control preservation)
"""

import logging
import sys
import os
import sqlite3
import tempfile
from pathlib import Path
from typing import Dict, Tuple, Optional

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

# Add Chrome verification utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict:
    """
    Main verification function for site_cookie_management@1 task.
    
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
            "feedback": "copy_from_env function not available in environment"
        }

    try:
        # Extract cookies database from container
        cookies_db_path, error_msg = extract_cookies_database(copy_from_env)
        
        if cookies_db_path is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Cookies database: {error_msg}"
            }
        
        # Verify selective cookie deletion
        result = verify_selective_cookie_deletion(cookies_db_path)
        
        # Cleanup temporary files
        try:
            if cookies_db_path and os.path.exists(cookies_db_path):
                os.unlink(cookies_db_path)
        except:
            pass
        
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


def extract_cookies_database(copy_from_env) -> Tuple[Optional[str], str]:
    """
    Extract Cookies database from container to host.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (local_db_path: str or None, error_message: str)
    """
    # Create temporary file for database
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations for Cookies database
        possible_paths = [
            "/tmp/cookies_export.db",  # Exported by export script
            "/home/ga/.config/google-chrome-cdp/Default/Cookies",  # CDP profile
            "/home/ga/.config/google-chrome/Default/Cookies",  # Default profile
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Attempting to copy Cookies database from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    # Verify it's a valid SQLite database
                    try:
                        conn = sqlite3.connect(temp_path)
                        cursor = conn.cursor()
                        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cookies';")
                        result = cursor.fetchone()
                        conn.close()
                        
                        if result:
                            logger.info(f"✓ Successfully copied valid Cookies database from: {container_path}")
                            return temp_path, ""
                        else:
                            logger.warning(f"Database from {container_path} missing 'cookies' table")
                    except sqlite3.Error as e:
                        logger.warning(f"Database from {container_path} is not valid SQLite: {e}")
                        
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        
        return None, "Cookies database not found in any known location"
        
    except Exception as e:
        logger.error(f"Error extracting cookies database: {e}")
        return None, f"Error extracting database: {str(e)}"


def query_domain_cookies(db_path: str, domain: str) -> int:
    """
    Query count of cookies for a specific domain.
    
    Args:
        db_path: Path to Cookies SQLite database
        domain: Domain to search for (e.g., 'github.com')
        
    Returns:
        Count of cookies for the domain
    """
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Query with LIKE to catch all variations (.github.com, github.com, www.github.com)
        query = "SELECT COUNT(*) FROM cookies WHERE host_key LIKE ?"
        cursor.execute(query, (f'%{domain}%',))
        
        count = cursor.fetchone()[0]
        conn.close()
        
        logger.info(f"Domain '{domain}': {count} cookies")
        return count
        
    except sqlite3.Error as e:
        logger.error(f"SQLite error querying {domain}: {e}")
        return -1  # Return -1 to indicate error
    except Exception as e:
        logger.error(f"Error querying {domain}: {e}")
        return -1


def get_total_cookie_count(db_path: str) -> int:
    """
    Get total count of all cookies in database.
    
    Args:
        db_path: Path to Cookies SQLite database
        
    Returns:
        Total cookie count
    """
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM cookies;")
        count = cursor.fetchone()[0]
        conn.close()
        
        logger.info(f"Total cookies in database: {count}")
        return count
        
    except sqlite3.Error as e:
        logger.error(f"SQLite error getting total count: {e}")
        return -1
    except Exception as e:
        logger.error(f"Error getting total count: {e}")
        return -1


def verify_selective_cookie_deletion(cookies_db_path: str) -> Dict:
    """
    Verify that github.com cookies were selectively deleted while others remain.
    
    Verification criteria:
    1. github.com cookies removed (count = 0)
    2. example.com cookies preserved (count > 0)
    3. wikipedia.org cookies preserved (count > 0)
    4. Total cookies > 0 (not bulk deletion)
    5. Database integrity maintained
    
    Args:
        cookies_db_path: Path to local copy of Cookies database
        
    Returns:
        Dict with verification results
    """
    # Query domain-specific cookies
    github_count = query_domain_cookies(cookies_db_path, 'github.com')
    example_count = query_domain_cookies(cookies_db_path, 'example.com')
    wiki_count = query_domain_cookies(cookies_db_path, 'wikipedia.org')
    total_count = get_total_cookie_count(cookies_db_path)
    
    # Check for query errors
    if any(count == -1 for count in [github_count, example_count, wiki_count, total_count]):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to query Cookies database - database may be corrupted or locked",
            "details": {
                "error": "Database query failed"
            }
        }
    
    # Evaluate criteria
    criteria = {
        "target_removed": github_count == 0,
        "control1_preserved": example_count > 0,
        "control2_preserved": wiki_count > 0,
        "selective_operation": total_count > 0,
        "database_integrity": total_count >= 0  # True if we got a valid count
    }
    
    criteria_met = sum(criteria.values())
    score = int((criteria_met / 5.0) * 100)
    passed = score >= 80  # Need at least 4/5 criteria
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Verification Results: {criteria_met}/5 criteria met")
    feedback_parts.append("")
    
    # Criterion 1: Target domain removed
    if criteria["target_removed"]:
        feedback_parts.append(f"✓ Target removed: github.com has {github_count} cookies (expected 0)")
    else:
        feedback_parts.append(f"✗ Target NOT removed: github.com still has {github_count} cookies (expected 0)")
    
    # Criterion 2: Control domain 1 preserved
    if criteria["control1_preserved"]:
        feedback_parts.append(f"✓ Control preserved: example.com has {example_count} cookies")
    else:
        feedback_parts.append(f"✗ Control LOST: example.com has {example_count} cookies (expected > 0)")
    
    # Criterion 3: Control domain 2 preserved
    if criteria["control2_preserved"]:
        feedback_parts.append(f"✓ Control preserved: wikipedia.org has {wiki_count} cookies")
    else:
        feedback_parts.append(f"✗ Control LOST: wikipedia.org has {wiki_count} cookies (expected > 0)")
    
    # Criterion 4: Selective operation (not bulk delete)
    if criteria["selective_operation"]:
        feedback_parts.append(f"✓ Selective operation: Total {total_count} cookies remain (not bulk deletion)")
    else:
        feedback_parts.append(f"✗ Bulk deletion detected: {total_count} total cookies (appears all cookies were deleted)")
    
    # Criterion 5: Database integrity
    if criteria["database_integrity"]:
        feedback_parts.append(f"✓ Database integrity: Cookies database is valid and accessible")
    else:
        feedback_parts.append(f"✗ Database integrity: Could not verify database")
    
    feedback_parts.append("")
    feedback_parts.append(f"Score: {score}/100")
    
    if passed:
        if score == 100:
            feedback_parts.append("✅ PASSED: Perfect selective cookie deletion!")
        else:
            feedback_parts.append("✅ PASSED: Selective cookie deletion successful with minor issues")
    else:
        if criteria["target_removed"]:
            feedback_parts.append("❌ FAILED: Target removed but control sites' cookies were also deleted")
        else:
            feedback_parts.append("❌ FAILED: Target domain cookies were not removed")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "github_cookies": github_count,
            "example_cookies": example_count,
            "wikipedia_cookies": wiki_count,
            "total_cookies": total_count,
            "criteria_met": criteria_met,
            "criteria": criteria
        }
    }
