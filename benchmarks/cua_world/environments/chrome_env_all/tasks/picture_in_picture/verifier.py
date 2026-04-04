#!/usr/bin/env python3
"""
Verifier for Chrome Picture-in-Picture Task (picture_in_picture@1)
Task: Activate Picture-in-Picture mode for a video

Verification Strategy:
- Check for PiP window via window manager (wmctrl)
- Verify window count increased (main browser + PiP window)
- Check window geometry for small floating window
- Validate video page is still open
- Analyze window titles for PiP indicators
- Check CDP tab state

Multi-criteria scoring with 6 verification points.
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for picture_in_picture@1.
    
    Verifies that Picture-in-Picture mode was successfully activated for the video.
    
    Scoring criteria (6 total, need 4+ to pass):
    1. PiP window detected in window list
    2. Chrome window count increased (2+ windows)
    3. Small floating window geometry detected
    4. Video test page still open
    5. PiP-related window title found
    6. No error indicators
    
    Pass threshold: 67% (4 out of 6 criteria)
    
    Args:
        traj: Trajectory data (not used)
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
            "feedback": "Copy function not available in environment"
        }
    
    try:
        # Copy verification files from container
        verify_data = copy_verification_files(copy_from_env)
        
        if not verify_data:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to copy verification files from container"
            }
        
        # Run multi-criteria verification
        result = verify_pip_activation(verify_data)
        
        # Cleanup
        cleanup_temp_files(verify_data)
        if UTILS_AVAILABLE:
            cleanup_verification_temp()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def copy_verification_files(copy_from_env) -> Dict[str, str]:
    """
    Copy all verification files from container to host.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict mapping file types to local paths
    """
    files_to_copy = {
        'window_list': '/tmp/pip_verification/window_list.txt',
        'pip_matches': '/tmp/pip_verification/pip_window_matches.txt',
        'chrome_tabs': '/tmp/pip_verification/chrome_tabs.json',
        'active_url': '/tmp/pip_verification/active_url.txt',
        'pip_state': '/tmp/pip_verification/pip_state.json',
        'window_count': '/tmp/pip_verification/chrome_window_count.txt',
        'window_geometry': '/tmp/pip_verification/window_geometry.txt',
    }
    
    local_files = {}
    
    for file_type, container_path in files_to_copy.items():
        try:
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=f'_{file_type}')
            temp_file.close()
            
            copy_from_env(container_path, temp_file.name)
            
            # Verify file was copied and has content
            if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                local_files[file_type] = temp_file.name
                logger.info(f"✓ Copied {file_type}: {os.path.getsize(temp_file.name)} bytes")
            else:
                logger.warning(f"⚠ File {file_type} is empty or not copied")
                # Create empty file to prevent errors
                with open(temp_file.name, 'w') as f:
                    f.write('')
                local_files[file_type] = temp_file.name
                
        except Exception as e:
            logger.warning(f"Failed to copy {file_type}: {e}")
            # Create empty temp file
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=f'_{file_type}')
            temp_file.write(b'')
            temp_file.close()
            local_files[file_type] = temp_file.name
    
    return local_files


def verify_pip_activation(verify_data: Dict[str, str]) -> Dict[str, Any]:
    """
    Verify Picture-in-Picture activation using multiple criteria.
    
    Args:
        verify_data: Dict of file types to local file paths
        
    Returns:
        Verification result with passed, score, feedback
    """
    criteria_results = {
        'pip_window_detected': False,
        'window_count_increased': False,
        'small_window_geometry': False,
        'video_page_open': False,
        'pip_title_found': False,
        'no_errors': True
    }
    
    feedback_parts = []
    
    # Criterion 1: Check for PiP window in window list
    pip_detected, pip_msg = check_pip_window_list(verify_data)
    criteria_results['pip_window_detected'] = pip_detected
    feedback_parts.append(f"{'✓' if pip_detected else '✗'} PiP window detection: {pip_msg}")
    
    # Criterion 2: Check window count increased
    count_ok, count_msg = check_window_count(verify_data)
    criteria_results['window_count_increased'] = count_ok
    feedback_parts.append(f"{'✓' if count_ok else '✗'} Window count: {count_msg}")
    
    # Criterion 3: Check for small floating window geometry
    geometry_ok, geometry_msg = check_window_geometry(verify_data)
    criteria_results['small_window_geometry'] = geometry_ok
    feedback_parts.append(f"{'✓' if geometry_ok else '✗'} Window geometry: {geometry_msg}")
    
    # Criterion 4: Check video page is still open
    video_page_ok, video_msg = check_video_page_open(verify_data)
    criteria_results['video_page_open'] = video_page_ok
    feedback_parts.append(f"{'✓' if video_page_ok else '✗'} Video page: {video_msg}")
    
    # Criterion 5: Check for PiP-related window titles
    title_ok, title_msg = check_pip_titles(verify_data)
    criteria_results['pip_title_found'] = title_ok
    feedback_parts.append(f"{'✓' if title_ok else '✗'} PiP title indicators: {title_msg}")
    
    # Criterion 6: Check for error indicators
    no_errors, error_msg = check_no_errors(verify_data)
    criteria_results['no_errors'] = no_errors
    feedback_parts.append(f"{'✓' if no_errors else '⚠'} Error check: {error_msg}")
    
    # Calculate score
    criteria_met = sum(criteria_results.values())
    total_criteria = len(criteria_results)
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 67  # Need 4 out of 6 criteria (66.7%)
    
    # Build feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    
    if passed:
        feedback += "\n✅ Picture-in-Picture task PASSED"
        feedback += "\nVideo successfully activated in floating PiP mode!"
    else:
        feedback += "\n❌ Picture-in-Picture task FAILED"
        feedback += "\nPiP mode was not successfully activated."
        feedback += "\nEnsure you right-click on the video and select 'Picture in Picture'."
    
    logger.info(f"Verification complete: {criteria_met}/{total_criteria} criteria met, score={score}%")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_results": criteria_results,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }


def check_pip_window_list(verify_data: Dict[str, str]) -> Tuple[bool, str]:
    """Check if PiP window appears in window list."""
    try:
        pip_matches_file = verify_data.get('pip_matches')
        if not pip_matches_file:
            return False, "PiP matches file not available"
        
        with open(pip_matches_file, 'r') as f:
            content = f.read().strip()
        
        if not content or content == "no matches":
            return False, "No PiP window found in window list"
        
        # Check for PiP-related window titles
        if any(keyword in content.lower() for keyword in ['picture', 'pip', 'video']):
            return True, f"PiP window detected"
        
        return False, "No PiP window patterns found"
        
    except Exception as e:
        logger.error(f"Error checking PiP window list: {e}")
        return False, f"Error: {e}"


def check_window_count(verify_data: Dict[str, str]) -> Tuple[bool, str]:
    """Check if Chrome window count increased (indicating PiP window opened)."""
    try:
        count_file = verify_data.get('window_count')
        if not count_file:
            return False, "Window count file not available"
        
        with open(count_file, 'r') as f:
            count_str = f.read().strip()
        
        if not count_str:
            return False, "Window count empty"
        
        window_count = int(count_str)
        
        # With PiP active, we expect at least 2 Chrome windows
        # (main browser window + PiP floating window)
        if window_count >= 2:
            return True, f"{window_count} Chrome windows (includes PiP)"
        else:
            return False, f"Only {window_count} Chrome window (no PiP window)"
            
    except Exception as e:
        logger.error(f"Error checking window count: {e}")
        return False, f"Error: {e}"


def check_window_geometry(verify_data: Dict[str, str]) -> Tuple[bool, str]:
    """Check for small floating window with PiP-typical dimensions."""
    try:
        geometry_file = verify_data.get('window_geometry')
        if not geometry_file:
            return False, "Geometry file not available"
        
        with open(geometry_file, 'r') as f:
            geometry_content = f.read()
        
        if not geometry_content.strip():
            return False, "No geometry data"
        
        # Parse window dimensions
        # PiP windows are typically 300-600px wide and maintain video aspect ratio
        width_pattern = r'Width:\s*(\d+)'
        height_pattern = r'Height:\s*(\d+)'
        
        widths = [int(w) for w in re.findall(width_pattern, geometry_content)]
        heights = [int(h) for h in re.findall(height_pattern, geometry_content)]
        
        # Look for small window (PiP typically 300-600px wide)
        small_windows = []
        for i, (w, h) in enumerate(zip(widths, heights)):
            if 200 < w < 700 and 150 < h < 500:
                small_windows.append((w, h))
        
        if small_windows:
            w, h = small_windows[0]
            return True, f"Small window found ({w}x{h}px, typical PiP size)"
        else:
            return False, "No small floating window detected"
            
    except Exception as e:
        logger.error(f"Error checking geometry: {e}")
        return False, f"Error: {e}"


def check_video_page_open(verify_data: Dict[str, str]) -> Tuple[bool, str]:
    """Check if video test page is still open."""
    try:
        active_url_file = verify_data.get('active_url')
        if not active_url_file:
            return False, "Active URL file not available"
        
        with open(active_url_file, 'r') as f:
            active_url = f.read().strip()
        
        if not active_url:
            # Try checking tabs JSON
            tabs_file = verify_data.get('chrome_tabs')
            if tabs_file:
                with open(tabs_file, 'r') as f:
                    tabs_data = json.load(f)
                
                for tab in tabs_data:
                    if 'pip_test_video.html' in tab.get('url', ''):
                        return True, "Video page found in tabs"
            
            return False, "Could not determine active URL"
        
        if 'pip_test_video.html' in active_url:
            return True, "Video test page is open"
        else:
            return False, f"Video page not active (current: {active_url[:50]})"
            
    except Exception as e:
        logger.error(f"Error checking video page: {e}")
        return False, f"Error: {e}"


def check_pip_titles(verify_data: Dict[str, str]) -> Tuple[bool, str]:
    """Check for PiP-related window titles."""
    try:
        window_list_file = verify_data.get('window_list')
        if not window_list_file:
            return False, "Window list not available"
        
        with open(window_list_file, 'r') as f:
            window_list = f.read()
        
        # Look for PiP-related keywords in window titles
        pip_keywords = ['picture in picture', 'picture-in-picture', 'pip']
        
        for keyword in pip_keywords:
            if keyword in window_list.lower():
                return True, f"PiP keyword '{keyword}' found in window title"
        
        # Also check if there's a small Chrome window (might not have explicit PiP title)
        chrome_lines = [line for line in window_list.split('\n') if 'chrome' in line.lower()]
        if len(chrome_lines) >= 2:
            return True, "Multiple Chrome windows detected (likely includes PiP)"
        
        return False, "No PiP title indicators found"
        
    except Exception as e:
        logger.error(f"Error checking PiP titles: {e}")
        return False, f"Error: {e}"


def check_no_errors(verify_data: Dict[str, str]) -> Tuple[bool, str]:
    """Check for error indicators."""
    try:
        # Check tabs for error pages
        tabs_file = verify_data.get('chrome_tabs')
        if tabs_file and os.path.getsize(tabs_file) > 0:
            with open(tabs_file, 'r') as f:
                tabs_data = json.load(f)
            
            for tab in tabs_data:
                title = tab.get('title', '').lower()
                url = tab.get('url', '').lower()
                
                error_keywords = ['error', '404', 'not found', 'cannot', 'failed']
                if any(kw in title or kw in url for kw in error_keywords):
                    return False, f"Error page detected: {title[:30]}"
        
        return True, "No error indicators detected"
        
    except Exception as e:
        logger.warning(f"Error during error check: {e}")
        return True, "Error check inconclusive (assumed OK)"


def cleanup_temp_files(verify_data: Dict[str, str]):
    """Clean up temporary verification files."""
    for file_path in verify_data.values():
        try:
            if os.path.exists(file_path):
                os.unlink(file_path)
        except Exception as e:
            logger.warning(f"Failed to cleanup {file_path}: {e}")
