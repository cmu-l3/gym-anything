#!/usr/bin/env python3
"""
Verifier for Chrome Network Throttling Configuration Task (network_throttling@1)
Task: Configure DevTools Network Throttling to Slow 3G preset

Verification Strategy:
1. Check if DevTools appears to be open (via CDP or screenshots)
2. Analyze screenshot for "Slow 3G" text using OCR
3. Look for Network panel indicators
4. Multi-criteria scoring for robustness

Criteria (5 total, need 3+ to pass):
- DevTools accessibility (CDP responding)
- DevTools appears open (window/screenshot evidence)
- "Slow 3G" or "slow 3g" detected in screenshot OCR
- Network panel indicators present
- No error state detected
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

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

# Try to import PIL for image analysis
try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    logger.warning("PIL not available, image analysis will be limited")
    HAS_PIL = False

# Try to import pytesseract for OCR
try:
    import pytesseract
    HAS_TESSERACT = True
except ImportError:
    logger.warning("pytesseract not available, OCR verification will be limited")
    HAS_TESSERACT = False


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for network_throttling@1 task.
    
    Args:
        traj: Trajectory data
        env_info: Environment information including copy_from_env
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
        # Collect verification data from container
        verification_data = collect_verification_data(copy_from_env)
        
        # Run multi-criteria verification
        result = verify_network_throttling(verification_data)
        
        # Cleanup
        cleanup_temp_files(verification_data)
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


def collect_verification_data(copy_from_env) -> Dict[str, Any]:
    """
    Collect all verification data from container.
    
    Returns:
        Dict with screenshots, OCR text, CDP data, etc.
    """
    data = {
        "screenshot_path": None,
        "chrome_window_path": None,
        "ocr_text": "",
        "cdp_tabs": [],
        "devtools_detected": False,
        "active_url": "",
        "tab_count": 0,
        "window_list": ""
    }
    
    temp_dir = Path(tempfile.mkdtemp(prefix="throttle_verify_"))
    
    try:
        # Copy screenshot
        screenshot_path = temp_dir / "final_screenshot.png"
        try:
            copy_from_env("/tmp/network_throttling_verification/final_screenshot.png", str(screenshot_path))
            if screenshot_path.exists() and screenshot_path.stat().st_size > 0:
                data["screenshot_path"] = str(screenshot_path)
                logger.info(f"✓ Screenshot copied: {screenshot_path.stat().st_size} bytes")
        except Exception as e:
            logger.warning(f"Could not copy screenshot: {e}")
            # Try alternative location
            try:
                copy_from_env("/tmp/final_screenshot.png", str(screenshot_path))
                if screenshot_path.exists():
                    data["screenshot_path"] = str(screenshot_path)
            except:
                pass
        
        # Copy Chrome window screenshot
        chrome_window_path = temp_dir / "chrome_window.png"
        try:
            copy_from_env("/tmp/network_throttling_verification/chrome_window.png", str(chrome_window_path))
            if chrome_window_path.exists() and chrome_window_path.stat().st_size > 0:
                data["chrome_window_path"] = str(chrome_window_path)
        except:
            pass
        
        # Copy OCR text
        ocr_path = temp_dir / "screenshot_text.txt"
        try:
            copy_from_env("/tmp/network_throttling_verification/screenshot_text.txt", str(ocr_path))
            if ocr_path.exists():
                with open(ocr_path, 'r', encoding='utf-8', errors='ignore') as f:
                    data["ocr_text"] = f.read()
                logger.info(f"✓ OCR text retrieved: {len(data['ocr_text'])} characters")
        except Exception as e:
            logger.debug(f"Could not copy OCR text: {e}")
        
        # Copy CDP tabs data
        tabs_path = temp_dir / "chrome_tabs.json"
        try:
            copy_from_env("/tmp/network_throttling_verification/chrome_tabs.json", str(tabs_path))
            if tabs_path.exists():
                with open(tabs_path, 'r') as f:
                    data["cdp_tabs"] = json.load(f)
                logger.info(f"✓ CDP tabs data retrieved: {len(data['cdp_tabs'])} items")
        except Exception as e:
            logger.debug(f"Could not copy CDP data: {e}")
        
        # Copy DevTools detection flag
        devtools_path = temp_dir / "devtools_detected.txt"
        try:
            copy_from_env("/tmp/network_throttling_verification/devtools_detected.txt", str(devtools_path))
            if devtools_path.exists():
                with open(devtools_path, 'r') as f:
                    data["devtools_detected"] = f.read().strip().lower() == "true"
        except:
            pass
        
        # Copy active URL
        url_path = temp_dir / "active_url.txt"
        try:
            copy_from_env("/tmp/network_throttling_verification/active_url.txt", str(url_path))
            if url_path.exists():
                with open(url_path, 'r') as f:
                    data["active_url"] = f.read().strip()
        except:
            pass
        
        # Copy tab count
        count_path = temp_dir / "tab_count.txt"
        try:
            copy_from_env("/tmp/network_throttling_verification/tab_count.txt", str(count_path))
            if count_path.exists():
                with open(count_path, 'r') as f:
                    data["tab_count"] = int(f.read().strip())
        except:
            pass
        
        # Copy window list
        window_path = temp_dir / "window_list.txt"
        try:
            copy_from_env("/tmp/network_throttling_verification/window_list.txt", str(window_path))
            if window_path.exists():
                with open(window_path, 'r') as f:
                    data["window_list"] = f.read()
        except:
            pass
        
        data["temp_dir"] = str(temp_dir)
        return data
        
    except Exception as e:
        logger.error(f"Error collecting verification data: {e}")
        return data


def verify_network_throttling(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Perform multi-criteria verification of network throttling configuration.
    
    Criteria:
    1. CDP accessible and responding
    2. DevTools appears to be open
    3. "Slow 3G" text detected in screenshot/OCR
    4. Network panel indicators present
    5. No error state detected
    
    Args:
        data: Verification data collected from container
        
    Returns:
        Result dict with passed, score, feedback
    """
    criteria_results = {}
    feedback_parts = []
    
    # Criterion 1: CDP accessible (tabs data retrieved)
    cdp_ok = len(data.get("cdp_tabs", [])) > 0
    criteria_results["cdp_accessible"] = cdp_ok
    if cdp_ok:
        feedback_parts.append("✓ Chrome DevTools Protocol accessible")
        logger.info("Criterion 1: CDP accessible - PASS")
    else:
        feedback_parts.append("✗ CDP not accessible or no tabs found")
        logger.info("Criterion 1: CDP accessible - FAIL")
    
    # Criterion 2: DevTools appears open
    devtools_open = data.get("devtools_detected", False)
    
    # Additional check: Look for DevTools in window list
    window_list = data.get("window_list", "").lower()
    if "devtools" in window_list or "developer tools" in window_list:
        devtools_open = True
    
    # Check if screenshot dimensions suggest DevTools is open (wider/taller window)
    if data.get("screenshot_path") and HAS_PIL:
        try:
            img = Image.open(data["screenshot_path"])
            width, height = img.size
            # If very wide or tall, might have DevTools docked
            if width > 1400 or height > 900:
                devtools_open = True
                logger.info("Screenshot dimensions suggest DevTools might be open")
        except:
            pass
    
    criteria_results["devtools_open"] = devtools_open
    if devtools_open:
        feedback_parts.append("✓ DevTools appears to be open")
        logger.info("Criterion 2: DevTools open - PASS")
    else:
        feedback_parts.append("✗ DevTools not detected as open")
        logger.info("Criterion 2: DevTools open - FAIL")
    
    # Criterion 3: "Slow 3G" detected in OCR or screenshot analysis
    slow_3g_detected = False
    detection_method = ""
    
    # Check OCR text
    ocr_text = data.get("ocr_text", "").lower()
    if ocr_text:
        # Look for various forms of "slow 3g"
        if re.search(r'slow.*3g|3g.*slow', ocr_text, re.IGNORECASE):
            slow_3g_detected = True
            detection_method = "OCR text"
        # Also check for just "3g" if near "slow"
        elif "3g" in ocr_text and "slow" in ocr_text:
            slow_3g_detected = True
            detection_method = "OCR keywords"
    
    # If we have pytesseract and a screenshot, try direct OCR
    if not slow_3g_detected and data.get("screenshot_path") and HAS_TESSERACT and HAS_PIL:
        try:
            img = Image.open(data["screenshot_path"])
            ocr_direct = pytesseract.image_to_string(img).lower()
            if re.search(r'slow.*3g|3g.*slow', ocr_direct, re.IGNORECASE):
                slow_3g_detected = True
                detection_method = "Direct OCR"
                logger.info("Direct OCR detected 'Slow 3G'")
        except Exception as e:
            logger.debug(f"Direct OCR failed: {e}")
    
    criteria_results["slow_3g_detected"] = slow_3g_detected
    if slow_3g_detected:
        feedback_parts.append(f"✓ 'Slow 3G' detected via {detection_method}")
        logger.info(f"Criterion 3: Slow 3G detected ({detection_method}) - PASS")
    else:
        feedback_parts.append("✗ 'Slow 3G' text not detected in screenshot")
        logger.info("Criterion 3: Slow 3G detected - FAIL")
    
    # Criterion 4: Network panel indicators
    network_panel_detected = False
    
    if ocr_text:
        # Look for "Network" tab/panel indicators
        if re.search(r'\bnetwork\b', ocr_text, re.IGNORECASE):
            network_panel_detected = True
            logger.info("'Network' keyword found in OCR")
    
    # Check for network-related UI text
    network_keywords = ["throttl", "no throttling", "network conditions", "network panel"]
    if any(kw in ocr_text for kw in network_keywords):
        network_panel_detected = True
    
    criteria_results["network_panel"] = network_panel_detected
    if network_panel_detected:
        feedback_parts.append("✓ Network panel indicators detected")
        logger.info("Criterion 4: Network panel indicators - PASS")
    else:
        feedback_parts.append("⚠ Network panel indicators not clearly detected")
        logger.info("Criterion 4: Network panel indicators - FAIL")
    
    # Criterion 5: No error state
    error_detected = False
    
    # Check for error keywords in OCR
    error_keywords = ["error", "failed", "cannot", "unable", "not responding"]
    if any(kw in ocr_text for kw in error_keywords):
        error_detected = True
    
    # Check active URL for error pages
    active_url = data.get("active_url", "").lower()
    if "chrome-error" in active_url or "errorpage" in active_url:
        error_detected = True
    
    no_errors = not error_detected
    criteria_results["no_errors"] = no_errors
    if no_errors:
        feedback_parts.append("✓ No error state detected")
        logger.info("Criterion 5: No errors - PASS")
    else:
        feedback_parts.append("✗ Error state detected")
        logger.info("Criterion 5: No errors - FAIL")
    
    # Calculate score
    total_criteria = 5
    criteria_met = sum([
        criteria_results["cdp_accessible"],
        criteria_results["devtools_open"],
        criteria_results["slow_3g_detected"],
        criteria_results["network_panel"],
        criteria_results["no_errors"]
    ])
    
    # Adjust scoring: Slow 3G detection is worth double
    if criteria_results["slow_3g_detected"]:
        criteria_met += 1  # Bonus point
        total_criteria += 1
    
    score = int((criteria_met / total_criteria) * 100)
    
    # Pass threshold: Need at least 3 base criteria OR Slow 3G detected + 2 others
    passed = (criteria_met >= 3) or (criteria_results["slow_3g_detected"] and sum(criteria_results.values()) >= 3)
    
    # If Slow 3G clearly detected, boost score
    if criteria_results["slow_3g_detected"]:
        score = max(score, 75)  # Ensure at least passing if Slow 3G detected
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'✅ PASSED' if passed else '❌ FAILED'}"
    
    if not HAS_TESSERACT:
        feedback += "\n\n⚠ Note: Tesseract OCR not available, verification may be less accurate"
    
    if not passed:
        feedback += "\n\nTroubleshooting:"
        if not criteria_results["devtools_open"]:
            feedback += "\n- Press F12 to open DevTools"
        if not criteria_results["network_panel"]:
            feedback += "\n- Click 'Network' tab in DevTools"
        if not criteria_results["slow_3g_detected"]:
            feedback += "\n- Select 'Slow 3G' from throttling dropdown"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria_met={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "criteria_results": criteria_results,
            "cdp_accessible": criteria_results["cdp_accessible"],
            "devtools_open": criteria_results["devtools_open"],
            "slow_3g_detected": criteria_results["slow_3g_detected"],
            "network_panel": criteria_results["network_panel"],
            "no_errors": criteria_results["no_errors"],
            "detection_method": detection_method if slow_3g_detected else "none"
        }
    }


def cleanup_temp_files(data: Dict[str, Any]):
    """Clean up temporary verification files"""
    try:
        temp_dir = data.get("temp_dir")
        if temp_dir and os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir)
            logger.info(f"Cleaned up temp dir: {temp_dir}")
    except Exception as e:
        logger.warning(f"Could not clean up temp files: {e}")
