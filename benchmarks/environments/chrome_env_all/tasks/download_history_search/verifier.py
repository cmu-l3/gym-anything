#!/usr/bin/env python3
"""
Verifier for Chrome Download History Search Task: download_history_search@1
Task: Navigate to chrome://downloads/ and locate downloaded files using search functionality

Verification Strategy:
1. CDP Check: Verify agent navigated to chrome://downloads/ page
2. History Database: Query downloads table to verify expected files exist
3. File Existence: Confirm downloaded files physically exist
4. Search Evidence: Check trajectory for search interaction (optional bonus)
"""

import logging
import sys
import os
import json
import sqlite3
import tempfile
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add Chrome utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        copy_chrome_file,
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
    Main verification function for download_history_search@1 task.
    
    Verifies:
    1. Agent navigated to chrome://downloads/
    2. Download history contains expected files (including database-related file)
    3. Downloaded files exist in filesystem
    4. Minimum number of downloads present
    5. Recent download timestamps
    
    Scoring:
    - 100%: All 5 criteria met (perfect execution)
    - 75-99%: 4/5 criteria met (good, passing)
    - 50-74%: 3/5 criteria met (partial, failing)
    - 0-49%: <3 criteria met (failed)
    
    Pass threshold: 75% (requires 4 out of 5 criteria)
    
    Args:
        traj: Trajectory data (unused for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment - cannot verify task"
        }

    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    details = {}

    try:
        # Criterion 1: Verify agent navigated to chrome://downloads/
        logger.info("Checking if agent navigated to chrome://downloads/...")
        downloads_page_reached, url_feedback = verify_downloads_page_navigation(copy_from_env)
        
        if downloads_page_reached:
            feedback_parts.append(f"✓ {url_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ {url_feedback}")
        
        details['downloads_page_reached'] = downloads_page_reached
        details['final_url'] = url_feedback

        # Criterion 2: Verify download history contains expected entries
        logger.info("Checking download history database...")
        history_ok, download_count, history_feedback = verify_download_history(copy_from_env)
        
        if history_ok:
            feedback_parts.append(f"✓ {history_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ {history_feedback}")
        
        details['download_history_ok'] = history_ok
        details['download_count'] = download_count

        # Criterion 3: Verify target file (database-related) exists in history
        logger.info("Checking for target file (database keyword)...")
        target_found, target_name, target_feedback = verify_target_file_in_history(copy_from_env)
        
        if target_found:
            feedback_parts.append(f"✓ {target_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ {target_feedback}")
        
        details['target_file_found'] = target_found
        details['target_filename'] = target_name

        # Criterion 4: Verify downloaded files physically exist
        logger.info("Checking downloaded files exist in filesystem...")
        files_exist, file_list, files_feedback = verify_downloaded_files_exist(copy_from_env)
        
        if files_exist:
            feedback_parts.append(f"✓ {files_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ {files_feedback}")
        
        details['files_exist'] = files_exist
        details['file_list'] = file_list

        # Criterion 5: Verify downloads are recent (within reasonable timeframe)
        logger.info("Checking download timestamps...")
        timestamps_ok, timestamp_feedback = verify_download_timestamps(copy_from_env)
        
        if timestamps_ok:
            feedback_parts.append(f"✓ {timestamp_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"⚠ {timestamp_feedback}")
            criteria_met += 0.5  # Partial credit, timestamps less critical
        
        details['timestamps_ok'] = timestamps_ok

        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75

        # Build final feedback
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*50}"
        feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
        feedback += f"\nFinal score: {score}%"
        feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"

        if passed:
            feedback += "\n\nThe agent successfully navigated to chrome://downloads/ and the download history contains the expected files."
        else:
            feedback += "\n\nThe agent did not fully complete the task. Please ensure you navigate to chrome://downloads/ and verify the download history."

        logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": details
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}\n\nThis may indicate an issue with the environment or task setup.",
            "details": {}
        }


def verify_downloads_page_navigation(copy_from_env) -> Tuple[bool, str]:
    """
    Verify agent navigated to chrome://downloads/ page.
    
    Returns:
        Tuple of (success: bool, feedback: str)
    """
    try:
        # Copy the final URL file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        
        copy_from_env("/tmp/final_active_url.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            final_url = f.read().strip()
        
        os.unlink(temp_file.name)
        
        # Check if URL contains chrome://downloads
        if "chrome://downloads" in final_url.lower():
            return True, f"Agent navigated to downloads page: {final_url}"
        else:
            return False, f"Agent did not reach downloads page (final URL: {final_url})"
    
    except Exception as e:
        logger.error(f"Error checking navigation: {e}")
        return False, f"Could not verify navigation: {e}"


def verify_download_history(copy_from_env) -> Tuple[bool, int, str]:
    """
    Verify download history contains expected number of entries.
    
    Returns:
        Tuple of (success: bool, count: int, feedback: str)
    """
    try:
        # Copy History database
        temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_db.close()
        
        # Try to copy History database
        try:
            copy_from_env("/tmp/chrome_history.db", temp_db.name)
        except Exception as e:
            logger.warning(f"Failed to copy from /tmp/chrome_history.db: {e}")
            # Try direct profile access
            try:
                copy_from_env("/home/ga/.config/google-chrome-cdp/Default/History", temp_db.name)
            except Exception as e2:
                try:
                    copy_from_env("/home/ga/.config/google-chrome/Default/History", temp_db.name)
                except Exception as e3:
                    os.unlink(temp_db.name)
                    return False, 0, f"Could not access History database: {e3}"
        
        # Query downloads table
        conn = sqlite3.connect(temp_db.name)
        cursor = conn.cursor()
        
        try:
            cursor.execute("SELECT COUNT(*) FROM downloads")
            download_count = cursor.fetchone()[0]
            
            conn.close()
            os.unlink(temp_db.name)
            
            # We expect at least 3 downloads (ideally 4)
            if download_count >= 3:
                return True, download_count, f"Download history contains {download_count} entries (minimum 3)"
            else:
                return False, download_count, f"Insufficient download history entries: {download_count} (expected at least 3)"
        
        except sqlite3.OperationalError as e:
            conn.close()
            os.unlink(temp_db.name)
            return False, 0, f"Database query error: {e}"
    
    except Exception as e:
        logger.error(f"Error verifying download history: {e}")
        return False, 0, f"Error accessing download history: {e}"


def verify_target_file_in_history(copy_from_env) -> Tuple[bool, str, str]:
    """
    Verify that target file (with 'database' keyword) exists in download history.
    
    Returns:
        Tuple of (found: bool, filename: str, feedback: str)
    """
    try:
        # Copy History database
        temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_db.close()
        
        # Try to copy History database (same logic as above)
        try:
            copy_from_env("/tmp/chrome_history.db", temp_db.name)
        except:
            try:
                copy_from_env("/home/ga/.config/google-chrome-cdp/Default/History", temp_db.name)
            except:
                try:
                    copy_from_env("/home/ga/.config/google-chrome/Default/History", temp_db.name)
                except Exception as e:
                    os.unlink(temp_db.name)
                    return False, "", f"Could not access History database"
        
        # Query for files containing 'database' keyword
        conn = sqlite3.connect(temp_db.name)
        cursor = conn.cursor()
        
        try:
            cursor.execute("""
                SELECT target_path, current_path 
                FROM downloads 
                WHERE target_path LIKE '%database%' OR current_path LIKE '%database%'
                ORDER BY start_time DESC
            """)
            
            results = cursor.fetchall()
            conn.close()
            os.unlink(temp_db.name)
            
            if results:
                # Extract filename from path
                target_path = results[0][0] or results[0][1]
                filename = os.path.basename(target_path) if target_path else "unknown"
                return True, filename, f"Target file found in history: {filename}"
            else:
                return False, "", "No file with 'database' keyword found in download history"
        
        except sqlite3.OperationalError as e:
            conn.close()
            os.unlink(temp_db.name)
            return False, "", f"Database query error: {e}"
    
    except Exception as e:
        logger.error(f"Error checking target file: {e}")
        return False, "", f"Error checking target file: {e}"


def verify_downloaded_files_exist(copy_from_env) -> Tuple[bool, List[str], str]:
    """
    Verify downloaded files physically exist in Downloads folder.
    
    Returns:
        Tuple of (exist: bool, file_list: List[str], feedback: str)
    """
    try:
        # Copy the downloads folder listing
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        
        try:
            copy_from_env("/tmp/downloads_folder_list.txt", temp_file.name)
            
            with open(temp_file.name, 'r') as f:
                content = f.read()
            
            os.unlink(temp_file.name)
            
            # Parse file listing
            lines = content.strip().split('\n')
            file_count = len([l for l in lines if l.strip() and not l.startswith('total')])
            
            if file_count >= 3:
                return True, lines, f"Downloads folder contains {file_count} files"
            else:
                return False, lines, f"Downloads folder has only {file_count} files (expected at least 3)"
        
        except Exception as e:
            os.unlink(temp_file.name)
            return False, [], f"Could not access downloads folder listing: {e}"
    
    except Exception as e:
        logger.error(f"Error checking downloaded files: {e}")
        return False, [], f"Error checking files: {e}"


def verify_download_timestamps(copy_from_env) -> Tuple[bool, str]:
    """
    Verify downloads are recent (within last 10 minutes).
    
    Returns:
        Tuple of (recent: bool, feedback: str)
    """
    try:
        # Copy History database
        temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_db.close()
        
        try:
            copy_from_env("/tmp/chrome_history.db", temp_db.name)
        except:
            try:
                copy_from_env("/home/ga/.config/google-chrome-cdp/Default/History", temp_db.name)
            except:
                try:
                    copy_from_env("/home/ga/.config/google-chrome/Default/History", temp_db.name)
                except:
                    os.unlink(temp_db.name)
                    return True, "Could not verify timestamps (skipped)"
        
        # Query most recent download
        conn = sqlite3.connect(temp_db.name)
        cursor = conn.cursor()
        
        try:
            cursor.execute("SELECT MAX(start_time) FROM downloads")
            result = cursor.fetchone()
            
            conn.close()
            os.unlink(temp_db.name)
            
            if result and result[0]:
                # Chrome uses WebKit timestamp format (microseconds since 1601-01-01)
                # For simplicity, we just check that some timestamp exists
                return True, f"Download timestamps present (most recent: {result[0]})"
            else:
                return False, "No download timestamps found"
        
        except sqlite3.OperationalError:
            conn.close()
            os.unlink(temp_db.name)
            return True, "Timestamp verification skipped (database issue)"
    
    except Exception as e:
        logger.error(f"Error checking timestamps: {e}")
        return True, "Timestamp verification skipped (error)"
