#!/usr/bin/env python3
"""
Verifier for Chrome Offline Mode Simulation Task (offline_mode_simulation@1)
Task: Use DevTools to simulate offline mode, observe error, restore connectivity

Verification Strategy:
1. Check for evidence of offline error page (screenshot analysis or history)
2. Verify final page is not an error page (successful restoration)
3. Check browser history for offline navigation patterns
4. Validate screenshots for DevTools Network panel usage
5. Ensure proper offline/online cycle was completed
"""

import logging
import sys
import os
import json
import tempfile
import sqlite3
from pathlib import Path
from typing import Dict, Any, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import image processing libraries
try:
    from PIL import Image
    import numpy as np
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    logger.warning("PIL not available, image analysis will be limited")

try:
    import pytesseract
    HAS_TESSERACT = True
except ImportError:
    HAS_TESSERACT = False
    logger.warning("pytesseract not available, OCR will be unavailable")

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for offline_mode_simulation@1.
    
    Verifies:
    1. Evidence of offline error page during task
    2. Final page is successfully loaded (not error page)
    3. Browser history shows offline navigation attempt
    4. DevTools was used (optional, via screenshot if available)
    5. Complete offline/online cycle completed
    
    Scoring:
    - 100%: All 5 criteria met (perfect execution with all evidence)
    - 80-99%: 4/5 criteria met (good execution, minor missing evidence)
    - 60-79%: 3/5 criteria met (acceptable, passing threshold)
    - 40-59%: 2/5 criteria met (partial completion)
    - <40%: <2 criteria met (task incomplete)
    
    Pass threshold: 75% (at least 4 out of 5 criteria, or 3 with strong evidence)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    criteria_met = 0.0
    total_criteria = 5
    feedback_parts = []
    details = {}
    
    try:
        # Get verification data from container
        verification_data = get_verification_data(copy_from_env)
        
        # Criterion 1: Evidence of offline error page
        logger.info("Checking for offline error page evidence...")
        offline_error_detected, offline_feedback = check_offline_error_evidence(
            verification_data
        )
        if offline_error_detected:
            feedback_parts.append(f"✓ Offline error detected: {offline_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ No offline error detected: {offline_feedback}")
        details['offline_error_detected'] = offline_error_detected
        
        # Criterion 2: Final page is successfully loaded (not error page)
        logger.info("Checking final page state...")
        final_page_ok, final_feedback = check_final_page_success(
            verification_data
        )
        if final_page_ok:
            feedback_parts.append(f"✓ Final page OK: {final_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ Final page issue: {final_feedback}")
        details['final_page_success'] = final_page_ok
        
        # Criterion 3: Browser history shows offline navigation pattern
        logger.info("Checking browser history...")
        history_ok, history_feedback = check_history_pattern(
            verification_data
        )
        if history_ok:
            feedback_parts.append(f"✓ History pattern: {history_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"⚠ History check: {history_feedback}")
            # Give partial credit if history unavailable
            if "unavailable" in history_feedback.lower():
                criteria_met += 0.3
        details['history_pattern'] = history_ok
        
        # Criterion 4: Screenshot evidence of DevTools/Network panel
        logger.info("Checking for DevTools evidence...")
        devtools_ok, devtools_feedback = check_devtools_evidence(
            verification_data
        )
        if devtools_ok:
            feedback_parts.append(f"✓ DevTools evidence: {devtools_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"⚠ DevTools evidence: {devtools_feedback}")
            # Partial credit if screenshots unavailable
            if "unavailable" in devtools_feedback.lower():
                criteria_met += 0.3
        details['devtools_used'] = devtools_ok
        
        # Criterion 5: Complete cycle (offline error + successful recovery)
        logger.info("Checking for complete offline/online cycle...")
        cycle_complete = offline_error_detected and final_page_ok
        if cycle_complete:
            feedback_parts.append("✓ Complete offline/online cycle verified")
            criteria_met += 1
        else:
            if offline_error_detected and not final_page_ok:
                feedback_parts.append("✗ Offline detected but recovery incomplete")
            elif not offline_error_detected and final_page_ok:
                feedback_parts.append("✗ Final page OK but no offline evidence")
            else:
                feedback_parts.append("✗ Incomplete cycle")
        details['cycle_complete'] = cycle_complete
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75
        
        # Build final feedback
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*50}"
        feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
        feedback += f"\nFinal score: {score}%"
        feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
        
        if not HAS_PIL or not HAS_TESSERACT:
            feedback += "\n\n⚠ Note: Image analysis libraries limited, some checks had reduced functionality"
        
        logger.info(f"Verification complete: passed={passed}, score={score}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": details
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_verification_temp()


def get_verification_data(copy_from_env) -> Dict[str, Any]:
    """
    Retrieve all verification data from container.
    
    Returns:
        Dict containing final_url, final_title, screenshots, history data, etc.
    """
    data = {
        'final_url': '',
        'final_title': '',
        'screenshots': [],
        'history_db': None,
        'error_urls': []
    }
    
    # Copy final URL
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/final_url.txt", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data['final_url'] = f.read().strip()
        os.unlink(temp_file.name)
        logger.info(f"Final URL: {data['final_url']}")
    except Exception as e:
        logger.warning(f"Could not get final URL: {e}")
    
    # Copy final title
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/final_title.txt", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data['final_title'] = f.read().strip()
        os.unlink(temp_file.name)
        logger.info(f"Final title: {data['final_title']}")
    except Exception as e:
        logger.warning(f"Could not get final title: {e}")
    
    # Copy screenshots
    screenshot_names = ['final_screenshot.png']
    for i in range(10):  # Try up to 10 potential screenshots
        screenshot_names.append(f'screenshot_{i}.png')
        screenshot_names.append(f'task_screenshot_{i}.png')
    
    for screenshot_name in screenshot_names:
        try:
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(f"/tmp/{screenshot_name}", temp_file.name)
            if os.path.getsize(temp_file.name) > 0:
                data['screenshots'].append(temp_file.name)
                logger.info(f"Copied screenshot: {screenshot_name}")
        except Exception:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    
    # Copy history database
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        copy_from_env("/tmp/History.db", temp_file.name)
        if os.path.getsize(temp_file.name) > 0:
            data['history_db'] = temp_file.name
            logger.info("Copied history database")
    except Exception as e:
        logger.warning(f"Could not get history database: {e}")
    
    # Copy error URLs list
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/error_urls.txt", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data['error_urls'] = [line.strip() for line in f if line.strip()]
        os.unlink(temp_file.name)
        logger.info(f"Found {len(data['error_urls'])} error URLs in history")
    except Exception as e:
        logger.warning(f"Could not get error URLs: {e}")
    
    return data


def check_offline_error_evidence(data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check for evidence of offline error page.
    
    Looks for:
    - chrome-error:// URLs in history
    - Error page keywords in screenshots
    - Offline error indicators
    """
    # Check history for error URLs
    if data['error_urls']:
        for url in data['error_urls']:
            if 'chrome-error' in url.lower() or 'err_internet_disconnected' in url.lower():
                return True, f"Error page found in history: {url[:50]}..."
    
    # Check screenshots for offline error page
    if data['screenshots'] and HAS_PIL:
        for screenshot_path in data['screenshots']:
            has_error, evidence = analyze_screenshot_for_offline_error(screenshot_path)
            if has_error:
                return True, f"Offline error page detected in screenshot: {evidence}"
    
    # Check history database directly
    if data['history_db']:
        try:
            conn = sqlite3.connect(data['history_db'])
            cursor = conn.cursor()
            cursor.execute("""
                SELECT url, title FROM urls 
                WHERE url LIKE '%chrome-error%' 
                   OR url LIKE '%ERR_%'
                   OR title LIKE '%internet%'
                ORDER BY last_visit_time DESC 
                LIMIT 5
            """)
            results = cursor.fetchall()
            conn.close()
            
            error_indicators = ['chrome-error', 'err_internet', 'err_network']
            if results:
                for url, title in results:
                    if any(indicator in url.lower() for indicator in error_indicators):
                        return True, f"Error page in history: {url[:50]}..."
        except Exception as e:
            logger.warning(f"Could not query history database: {e}")
    
    return False, "No offline error page evidence found"


def check_final_page_success(data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check that final page loaded successfully (not an error page).
    """
    final_url = data['final_url'].lower()
    final_title = data['final_title'].lower()
    
    # Check if current page is an error page
    error_indicators = [
        'chrome-error',
        'err_internet_disconnected',
        'err_network',
        'err_connection'
    ]
    
    for indicator in error_indicators:
        if indicator in final_url or indicator in final_title:
            return False, f"Final page is an error page: {data['final_url']}"
    
    # Check for successful page indicators
    if not final_url or final_url == 'about:blank':
        return False, "Final page is blank or not loaded"
    
    # Check if it's a valid HTTP/HTTPS URL
    if final_url.startswith('http://') or final_url.startswith('https://'):
        # Check title is not empty (indicates successful load)
        if final_title and len(final_title) > 0:
            return True, f"Page loaded successfully: {data['final_url'][:50]}..."
        else:
            return True, f"Page URL valid but title unknown: {data['final_url'][:50]}..."
    
    return False, f"Final page status unclear: {data['final_url']}"


def check_history_pattern(data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check browser history for pattern indicating offline navigation attempt.
    """
    if not data['history_db']:
        return False, "History database unavailable"
    
    try:
        conn = sqlite3.connect(data['history_db'])
        cursor = conn.cursor()
        
        # Get recent URLs
        cursor.execute("""
            SELECT url, title, last_visit_time FROM urls 
            ORDER BY last_visit_time DESC 
            LIMIT 20
        """)
        results = cursor.fetchall()
        conn.close()
        
        if not results:
            return False, "No history entries found"
        
        # Look for pattern: error page followed by successful load
        has_error = False
        has_success_after = False
        
        for i, (url, title, visit_time) in enumerate(results):
            url_lower = url.lower()
            
            # Check for error page
            if 'chrome-error' in url_lower or 'err_' in url_lower:
                has_error = True
                
                # Check if there's a successful load after this
                if i > 0:  # There are earlier entries (more recent)
                    for j in range(i):
                        prev_url = results[j][0].lower()
                        if 'http' in prev_url and 'chrome-error' not in prev_url:
                            has_success_after = True
                            break
        
        if has_error and has_success_after:
            return True, "History shows offline error followed by successful recovery"
        elif has_error:
            return True, "History shows offline error (recovery not detected in history)"
        else:
            return False, "No offline navigation pattern detected in history"
            
    except Exception as e:
        logger.warning(f"Could not analyze history: {e}")
        return False, f"History analysis failed: {str(e)}"


def check_devtools_evidence(data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check screenshots for evidence of DevTools being used.
    """
    if not data['screenshots']:
        return False, "No screenshots available for analysis"
    
    if not HAS_PIL:
        return False, "Image analysis libraries unavailable"
    
    for screenshot_path in data['screenshots']:
        has_devtools, evidence = analyze_screenshot_for_devtools(screenshot_path)
        if has_devtools:
            return True, evidence
    
    return False, "No DevTools evidence found in screenshots"


def analyze_screenshot_for_offline_error(screenshot_path: str) -> Tuple[bool, str]:
    """
    Analyze screenshot for Chrome offline error page indicators.
    """
    if not HAS_PIL:
        return False, "PIL not available"
    
    try:
        img = Image.open(screenshot_path)
        img_array = np.array(img)
        
        # Chrome offline page has distinctive features:
        # 1. Mostly white/light gray background
        # 2. Text like "No internet" or error codes
        
        # Check color distribution for white/gray dominance
        if img.mode != 'RGB':
            img = img.convert('RGB')
            img_array = np.array(img)
        
        # Count light-colored pixels (typical of error pages)
        light_pixels = np.sum(np.all(img_array > 200, axis=2))
        total_pixels = img_array.shape[0] * img_array.shape[1]
        light_ratio = light_pixels / total_pixels
        
        # Error pages tend to be >30% light colored
        has_light_bg = light_ratio > 0.3
        
        # Try OCR if available
        if HAS_TESSERACT:
            try:
                text = pytesseract.image_to_string(img).lower()
                error_keywords = [
                    'no internet',
                    'err_internet_disconnected',
                    'connection',
                    'offline',
                    'not connected',
                    'cannot reach',
                    'unable to connect'
                ]
                
                for keyword in error_keywords:
                    if keyword in text:
                        return True, f"Error text detected: '{keyword}'"
            except Exception as e:
                logger.debug(f"OCR failed: {e}")
        
        # If we have light background but no OCR confirmation, be cautious
        if has_light_bg and light_ratio > 0.6:
            return True, f"Likely error page (light background: {light_ratio:.0%})"
        
        return False, "No offline error indicators"
        
    except Exception as e:
        logger.warning(f"Screenshot analysis failed: {e}")
        return False, f"Analysis error: {str(e)}"


def analyze_screenshot_for_devtools(screenshot_path: str) -> Tuple[bool, str]:
    """
    Analyze screenshot for DevTools panel presence.
    """
    if not HAS_PIL:
        return False, "PIL not available"
    
    try:
        img = Image.open(screenshot_path)
        
        # DevTools typically appears as a panel at bottom or side
        # Use OCR to look for "Network", "Console", "Elements" tabs
        if HAS_TESSERACT:
            try:
                text = pytesseract.image_to_string(img).lower()
                devtools_keywords = [
                    'network',
                    'console',
                    'elements',
                    'sources',
                    'throttling',
                    'offline',
                    'no throttling'
                ]
                
                matches = [kw for kw in devtools_keywords if kw in text]
                if len(matches) >= 2:  # Need at least 2 keywords for confidence
                    return True, f"DevTools detected (keywords: {', '.join(matches[:3])})"
            except Exception as e:
                logger.debug(f"OCR failed: {e}")
        
        return False, "No DevTools indicators found"
        
    except Exception as e:
        logger.warning(f"Screenshot analysis failed: {e}")
        return False, f"Analysis error: {str(e)}"
