#!/usr/bin/env python3
"""
Verifier for Chrome Selective Privacy Clear Task (selective_privacy_clear@1)
Task: Clear sensitive browsing data (history, cookies, cache) while preserving bookmarks

Verification Strategy:
- Check History database is nearly empty (≤5 entries)
- Check Cookies database is nearly empty (≤10 entries)
- Check Cache is cleared (size < 5MB, files < 50)
- Check Bookmarks file exists and contains preserved bookmarks (≥3 entries)
- Ensure data integrity of all files

Scoring:
- 100%: All 5 criteria met (perfect selective clearing)
- 80%+: 4/5 criteria met (good, passing)
- 60-79%: 3/5 criteria met (adequate but failing)
- <60%: <3 criteria met (task failed)

Pass threshold: 80% (requires at least 4 out of 5 criteria)
"""

import logging
import sys
import os
import json
import sqlite3
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for selective_privacy_clear@1.
    
    Verifies that:
    1. History was cleared (≤5 entries remaining)
    2. Cookies were cleared (≤10 entries remaining)
    3. Cache was cleared (size < 5MB or files < 50)
    4. Bookmarks were preserved (≥3 entries)
    5. All files have data integrity
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment info with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, feedback, and details
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }

    try:
        # Copy Chrome data files from container
        files = copy_chrome_data_files(copy_from_env)
        
        if not files:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to copy Chrome data files from container"
            }
        
        # Verify each criterion
        criteria_results = {}
        feedback_parts = []
        
        # Criterion 1: History cleared
        history_cleared, history_count, history_msg = verify_history_cleared(files.get('history'))
        criteria_results['history_cleared'] = history_cleared
        feedback_parts.append(f"{'✓' if history_cleared else '✗'} History: {history_msg}")
        logger.info(f"History verification: {history_cleared} ({history_count} entries)")
        
        # Criterion 2: Cookies cleared
        cookies_cleared, cookie_count, cookies_msg = verify_cookies_cleared(files.get('cookies'))
        criteria_results['cookies_cleared'] = cookies_cleared
        feedback_parts.append(f"{'✓' if cookies_cleared else '✗'} Cookies: {cookies_msg}")
        logger.info(f"Cookies verification: {cookies_cleared} ({cookie_count} entries)")
        
        # Criterion 3: Cache cleared
        cache_cleared, cache_info, cache_msg = verify_cache_cleared(files.get('cache_size'), files.get('cache_files'))
        criteria_results['cache_cleared'] = cache_cleared
        feedback_parts.append(f"{'✓' if cache_cleared else '✗'} Cache: {cache_msg}")
        logger.info(f"Cache verification: {cache_cleared} ({cache_info})")
        
        # Criterion 4: Bookmarks preserved
        bookmarks_preserved, bookmark_count, bookmarks_msg = verify_bookmarks_preserved(files.get('bookmarks'))
        criteria_results['bookmarks_preserved'] = bookmarks_preserved
        feedback_parts.append(f"{'✓' if bookmarks_preserved else '✗'} Bookmarks: {bookmarks_msg}")
        logger.info(f"Bookmarks verification: {bookmarks_preserved} ({bookmark_count} entries)")
        
        # Criterion 5: Data integrity
        data_integrity, integrity_msg = verify_data_integrity(files)
        criteria_results['data_integrity'] = data_integrity
        feedback_parts.append(f"{'✓' if data_integrity else '✗'} Integrity: {integrity_msg}")
        logger.info(f"Data integrity: {data_integrity}")
        
        # Calculate score
        criteria_met = sum(criteria_results.values())
        total_criteria = len(criteria_results)
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 80  # Need at least 4/5 criteria
        
        # Build feedback
        feedback_header = f"Selective Privacy Clear Verification: {criteria_met}/{total_criteria} criteria met\n"
        feedback_header += "="*60 + "\n"
        feedback_body = "\n".join(feedback_parts)
        feedback_footer = f"\n{'='*60}\n"
        feedback_footer += f"Score: {score}% | Result: {'PASSED ✓' if passed else 'FAILED ✗'}\n"
        
        if passed:
            feedback_footer += "\nSuccessfully cleared sensitive data while preserving bookmarks!"
        else:
            feedback_footer += "\nTask incomplete: Some criteria not met."
            if not criteria_results['history_cleared']:
                feedback_footer += "\n  → History was not properly cleared"
            if not criteria_results['cookies_cleared']:
                feedback_footer += "\n  → Cookies were not properly cleared"
            if not criteria_results['cache_cleared']:
                feedback_footer += "\n  → Cache was not properly cleared"
            if not criteria_results['bookmarks_preserved']:
                feedback_footer += "\n  → Bookmarks were not preserved (damaged or deleted)"
        
        feedback = feedback_header + feedback_body + feedback_footer
        
        # Cleanup temp files
        cleanup_temp_files(files)
        cleanup_verification_temp()
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "criteria_met": criteria_met,
                "criteria_results": criteria_results,
                "history_count": history_count,
                "cookie_count": cookie_count,
                "bookmark_count": bookmark_count,
                "cache_info": cache_info
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def copy_chrome_data_files(copy_from_env) -> Dict[str, str]:
    """
    Copy Chrome data files from container to host for verification.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict mapping file types to local temp file paths
    """
    files = {}
    
    container_paths = {
        'history': '/tmp/privacy_clear_verification/History',
        'cookies': '/tmp/privacy_clear_verification/Cookies',
        'bookmarks': '/tmp/privacy_clear_verification/Bookmarks',
        'preferences': '/tmp/privacy_clear_verification/Preferences',
        'cache_size': '/tmp/privacy_clear_verification/cache_size.txt',
        'cache_files': '/tmp/privacy_clear_verification/cache_files.txt'
    }
    
    for file_type, container_path in container_paths.items():
        try:
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=f'_{file_type}')
            temp_file.close()
            
            copy_from_env(container_path, temp_file.name)
            
            # Verify file exists and has content
            if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) >= 0:
                files[file_type] = temp_file.name
                logger.info(f"✓ Copied {file_type} from container")
            else:
                logger.warning(f"⚠ {file_type} file empty or missing")
                files[file_type] = None
                
        except Exception as e:
            logger.warning(f"⚠ Could not copy {file_type}: {e}")
            files[file_type] = None
    
    return files


def verify_history_cleared(history_path: Optional[str]) -> Tuple[bool, int, str]:
    """
    Verify that browsing history was cleared.
    
    Args:
        history_path: Path to History SQLite database
        
    Returns:
        Tuple of (cleared: bool, count: int, message: str)
    """
    if not history_path or not os.path.exists(history_path):
        return False, -1, "History database not found"
    
    try:
        # Check if file is essentially empty (just structure)
        file_size = os.path.getsize(history_path)
        if file_size < 1024:  # Less than 1KB
            return True, 0, "Cleared (database empty)"
        
        # Query URLs table
        conn = sqlite3.connect(history_path)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM urls")
        url_count = cursor.fetchone()[0]
        conn.close()
        
        # Allow up to 5 entries (might be system URLs or residual)
        if url_count <= 5:
            return True, url_count, f"Cleared ({url_count} entries remain)"
        else:
            return False, url_count, f"Not cleared ({url_count} entries still present)"
            
    except sqlite3.DatabaseError as e:
        logger.error(f"Database error: {e}")
        return False, -1, f"Database corrupted or locked"
    except Exception as e:
        logger.error(f"Error checking history: {e}")
        return False, -1, f"Error: {str(e)}"


def verify_cookies_cleared(cookies_path: Optional[str]) -> Tuple[bool, int, str]:
    """
    Verify that cookies were cleared.
    
    Args:
        cookies_path: Path to Cookies SQLite database
        
    Returns:
        Tuple of (cleared: bool, count: int, message: str)
    """
    if not cookies_path or not os.path.exists(cookies_path):
        return False, -1, "Cookies database not found"
    
    try:
        # Check if file is essentially empty
        file_size = os.path.getsize(cookies_path)
        if file_size < 1024:  # Less than 1KB
            return True, 0, "Cleared (database empty)"
        
        # Query cookies table
        conn = sqlite3.connect(cookies_path)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM cookies")
        cookie_count = cursor.fetchone()[0]
        conn.close()
        
        # Allow up to 10 cookies (might be system cookies)
        if cookie_count <= 10:
            return True, cookie_count, f"Cleared ({cookie_count} cookies remain)"
        else:
            return False, cookie_count, f"Not cleared ({cookie_count} cookies still present)"
            
    except sqlite3.DatabaseError as e:
        logger.error(f"Database error: {e}")
        return False, -1, "Database corrupted or locked"
    except Exception as e:
        logger.error(f"Error checking cookies: {e}")
        return False, -1, f"Error: {str(e)}"


def verify_cache_cleared(cache_size_path: Optional[str], cache_files_path: Optional[str]) -> Tuple[bool, str, str]:
    """
    Verify that cache was cleared.
    
    Args:
        cache_size_path: Path to file containing cache size in bytes
        cache_files_path: Path to file containing cache file count
        
    Returns:
        Tuple of (cleared: bool, info: str, message: str)
    """
    try:
        # Read cache size
        if cache_size_path and os.path.exists(cache_size_path):
            with open(cache_size_path, 'r') as f:
                cache_size = int(f.read().strip())
        else:
            cache_size = 0
        
        # Read cache file count
        if cache_files_path and os.path.exists(cache_files_path):
            with open(cache_files_path, 'r') as f:
                cache_files = int(f.read().strip())
        else:
            cache_files = 0
        
        cache_size_mb = cache_size / (1024 * 1024)
        info = f"{cache_size_mb:.2f} MB, {cache_files} files"
        
        # Cache is cleared if size < 5MB AND files < 50
        if cache_size_mb < 5 and cache_files < 50:
            return True, info, f"Cleared ({info})"
        else:
            return False, info, f"Not cleared ({info})"
            
    except Exception as e:
        logger.error(f"Error checking cache: {e}")
        return False, "unknown", f"Error: {str(e)}"


def verify_bookmarks_preserved(bookmarks_path: Optional[str]) -> Tuple[bool, int, str]:
    """
    Verify that bookmarks were preserved.
    
    Args:
        bookmarks_path: Path to Bookmarks JSON file
        
    Returns:
        Tuple of (preserved: bool, count: int, message: str)
    """
    if not bookmarks_path or not os.path.exists(bookmarks_path):
        return False, 0, "Bookmarks file not found (deleted or damaged)"
    
    try:
        with open(bookmarks_path, 'r', encoding='utf-8') as f:
            bookmarks = json.load(f)
        
        # Count bookmark entries
        bookmark_bar = bookmarks.get('roots', {}).get('bookmark_bar', {})
        children = bookmark_bar.get('children', [])
        
        # Count all bookmarks recursively
        def count_bookmarks(items):
            count = 0
            for item in items:
                if item.get('type') == 'url':
                    count += 1
                elif item.get('type') == 'folder':
                    count += len(item.get('children', []))
                    count += count_bookmarks(item.get('children', []))
            return count
        
        total_bookmarks = count_bookmarks(children)
        
        # Check for specific folders/bookmarks from setup
        has_work_folder = any(c.get('name') == 'Important Work Sites' for c in children if c.get('type') == 'folder')
        has_personal_folder = any(c.get('name') == 'Personal Resources' for c in children if c.get('type') == 'folder')
        
        # Need at least 3 bookmark entries total
        if total_bookmarks >= 3:
            details = []
            if has_work_folder:
                details.append("Work Sites folder")
            if has_personal_folder:
                details.append("Personal folder")
            
            detail_str = ", ".join(details) if details else "bookmarks"
            return True, total_bookmarks, f"Preserved ({total_bookmarks} {detail_str})"
        else:
            return False, total_bookmarks, f"Damaged or deleted ({total_bookmarks} bookmarks, expected ≥3)"
            
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
        return False, 0, "Bookmarks file corrupted (invalid JSON)"
    except Exception as e:
        logger.error(f"Error checking bookmarks: {e}")
        return False, 0, f"Error: {str(e)}"


def verify_data_integrity(files: Dict[str, str]) -> Tuple[bool, str]:
    """
    Verify overall data integrity of Chrome files.
    
    Args:
        files: Dict of file types to paths
        
    Returns:
        Tuple of (integrity_ok: bool, message: str)
    """
    issues = []
    
    # Check that key files exist
    if not files.get('history'):
        issues.append("History file missing")
    if not files.get('cookies'):
        issues.append("Cookies file missing")
    if not files.get('bookmarks'):
        issues.append("Bookmarks file missing")
    
    if issues:
        return False, f"Files missing: {', '.join(issues)}"
    
    # Check that files are accessible
    for file_type, path in files.items():
        if path and os.path.exists(path):
            try:
                # Try to read a bit to ensure file isn't corrupted
                with open(path, 'rb') as f:
                    f.read(10)
            except Exception as e:
                issues.append(f"{file_type} unreadable")
    
    if issues:
        return False, f"Files damaged: {', '.join(issues)}"
    
    return True, "All files accessible"


def cleanup_temp_files(files: Dict[str, str]):
    """Clean up temporary files created during verification."""
    for path in files.values():
        if path and os.path.exists(path):
            try:
                os.unlink(path)
            except Exception as e:
                logger.warning(f"Could not delete temp file {path}: {e}")
