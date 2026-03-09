#!/usr/bin/env python3
"""
Verifier for Chrome Clear Cache Fix Task: clear_cache_fix@1
Task: Clear site-specific cache and cookies for example-site.com to fix loading issues

Verification Strategy:
1. Copy Cookies SQLite database from container
2. Query to check cookies for example-site.com (should be 0)
3. Query to check cookies for other pre-seeded sites (should be >0)
4. Verify selective deletion was used (total cookies > 0)
5. Calculate score based on criteria met

Scoring:
- Target domain cleared: 25 points
- Other sites preserved: 25 points
- Selective approach (not global clear): 25 points
- At least 2 other domains still have cookies: 25 points
Total: 100 points, Pass threshold: 75 points (3/4 criteria)
"""

import logging
import sys
import os
import sqlite3
import tempfile
from pathlib import Path
from typing import Dict, List, Tuple, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        cleanup_verification_temp,
        parse_cookies
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


# Target site that should be cleared
TARGET_DOMAIN = "example-site.com"

# Sites that should be preserved (pre-seeded in setup)
PRESERVE_DOMAINS = ["google.com", "wikipedia.org", "github.com", "stackoverflow.com"]


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for clear_cache_fix@1 task.
    
    Verifies:
    1. Target domain (example-site.com) has no cookies
    2. Other domains still have their cookies preserved
    3. Selective clearing was used (not global "Clear all")
    4. At least 2+ other sites still have data
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get cookies data from container
        cookies_db_path = get_cookies_database(copy_from_env)
        if cookies_db_path is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve Cookies database from container"
            }
        
        # Perform verification
        result = verify_selective_cache_clearing(cookies_db_path)
        
        # Clean up temporary files
        try:
            if os.path.exists(cookies_db_path):
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


def get_cookies_database(copy_from_env) -> str:
    """
    Copy Chrome Cookies database from container to host.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Path to local Cookies database file, or None on failure
    """
    try:
        # Create temporary file for cookies database
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_cookies_export.db",
            "/home/ga/.config/google-chrome-cdp/Default/Cookies",
            "/home/ga/.config/google-chrome/Default/Cookies"
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Cookies from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Verify file was copied and has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    logger.info(f"✓ Successfully copied Cookies database from: {container_path}")
                    return temp_path
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        # If we get here, all attempts failed
        os.unlink(temp_path)
        logger.error("Could not copy Cookies database from any location")
        return None
        
    except Exception as e:
        logger.error(f"Error getting Cookies database: {e}")
        return None


def query_cookies_for_domain(db_path: str, domain: str) -> int:
    """
    Query the number of cookies for a specific domain.
    
    Args:
        db_path: Path to Cookies SQLite database
        domain: Domain to check (e.g., "example-site.com")
        
    Returns:
        Number of cookies found for the domain
    """
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Query cookies where host_key contains the domain
        cursor.execute(
            "SELECT COUNT(*) FROM cookies WHERE host_key LIKE ?",
            (f"%{domain}%",)
        )
        count = cursor.fetchone()[0]
        conn.close()
        
        logger.info(f"Domain '{domain}': {count} cookie(s)")
        return count
        
    except Exception as e:
        logger.error(f"Error querying cookies for {domain}: {e}")
        return -1  # Return -1 to indicate error


def get_all_cookie_domains(db_path: str) -> List[str]:
    """
    Get all unique domains that have cookies.
    
    Args:
        db_path: Path to Cookies SQLite database
        
    Returns:
        List of unique domain names
    """
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        cursor.execute("SELECT DISTINCT host_key FROM cookies")
        domains = [row[0] for row in cursor.fetchall()]
        conn.close()
        
        logger.info(f"Found {len(domains)} unique domains with cookies")
        return domains
        
    except Exception as e:
        logger.error(f"Error getting cookie domains: {e}")
        return []


def count_total_cookies(db_path: str) -> int:
    """
    Count total number of cookies in database.
    
    Args:
        db_path: Path to Cookies SQLite database
        
    Returns:
        Total cookie count
    """
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        cursor.execute("SELECT COUNT(*) FROM cookies")
        count = cursor.fetchone()[0]
        conn.close()
        
        logger.info(f"Total cookies in database: {count}")
        return count
        
    except Exception as e:
        logger.error(f"Error counting total cookies: {e}")
        return 0


def verify_selective_cache_clearing(cookies_db_path: str) -> Dict[str, Any]:
    """
    Verify that site-specific cache clearing was performed correctly.
    
    Checks 4 criteria:
    1. Target domain (example-site.com) has 0 cookies
    2. At least 2 other pre-seeded domains still have cookies
    3. Total cookies > 0 (proving selective deletion, not global clear)
    4. At least 50% of pre-seeded domains preserved
    
    Args:
        cookies_db_path: Path to Cookies SQLite database
        
    Returns:
        Verification result with passed, score, and feedback
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: Target domain cleared
    target_count = query_cookies_for_domain(cookies_db_path, TARGET_DOMAIN)
    if target_count == -1:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to query Cookies database - may be corrupted"
        }
    
    target_cleared = (target_count == 0)
    if target_cleared:
        feedback_parts.append(f"✓ Target site cleared: {TARGET_DOMAIN} has 0 cookies")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Target site NOT cleared: {TARGET_DOMAIN} still has {target_count} cookie(s)")
    
    # Criterion 2 & 4: Check preservation of other sites
    preserved_domains = []
    for domain in PRESERVE_DOMAINS:
        count = query_cookies_for_domain(cookies_db_path, domain)
        if count > 0:
            preserved_domains.append(domain)
    
    at_least_two_preserved = len(preserved_domains) >= 2
    if at_least_two_preserved:
        feedback_parts.append(f"✓ Other sites preserved: {len(preserved_domains)} sites still have cookies ({', '.join(preserved_domains)})")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Too few sites preserved: Only {len(preserved_domains)} site(s) have cookies (need 2+)")
    
    # Criterion 3: Selective deletion (not global clear all)
    total_cookies = count_total_cookies(cookies_db_path)
    selective_approach = total_cookies > 0
    
    if selective_approach:
        feedback_parts.append(f"✓ Selective approach used: {total_cookies} total cookies remain")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Global clear detected: No cookies remain (all data was cleared)")
    
    # Criterion 4: At least 50% of pre-seeded domains preserved
    preservation_rate = len(preserved_domains) / len(PRESERVE_DOMAINS)
    good_preservation = preservation_rate >= 0.5
    
    if good_preservation:
        feedback_parts.append(f"✓ Good preservation rate: {len(preserved_domains)}/{len(PRESERVE_DOMAINS)} sites preserved ({preservation_rate*100:.0f}%)")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Poor preservation: Only {len(preserved_domains)}/{len(PRESERVE_DOMAINS)} sites preserved ({preservation_rate*100:.0f}%)")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3 out of 4 criteria
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    
    if passed:
        feedback += f"\nResult: ✅ PASSED - Site-specific cache clearing successful!"
    else:
        feedback += f"\nResult: ❌ FAILED - Task requirements not met"
    
    # Add detailed information
    all_domains = get_all_cookie_domains(cookies_db_path)
    feedback += f"\n\nAll domains with cookies: {', '.join(all_domains[:10])}"
    if len(all_domains) > 10:
        feedback += f" ... and {len(all_domains) - 10} more"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "target_cleared": target_cleared,
            "target_cookie_count": target_count,
            "preserved_domains": preserved_domains,
            "preservation_count": len(preserved_domains),
            "total_cookies": total_cookies,
            "selective_approach": selective_approach,
            "preservation_rate": preservation_rate,
            "all_domains": all_domains
        }
    }
