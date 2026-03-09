#!/usr/bin/env python3
"""
Verifier for Chrome Complete Webpage Save Task (save_webpage_complete@1)
Task: Save complete webpage with all resources using 'Webpage, Complete' format

Verification Strategy:
- Check Downloads folder for HTML file (demo_page.html)
- Check for companion resources folder (demo_page_files/)
- Verify folder contains multiple resource files
- Categorize resources by type (images, CSS, JS)
- Check HTML file size is reasonable
- Ensure minimum resource count threshold
"""

import logging
import sys
import os
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for save_webpage_complete@1 task.
    
    Verifies:
    1. HTML file exists in Downloads
    2. Resources folder exists
    3. Folder contains minimum 3 resources
    4. Resources include expected types (images, CSS, JS)
    5. HTML file has reasonable size
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment info with copy_from_env function
        task_info: Task configuration info
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    try:
        # Verify the complete save
        result = verify_complete_webpage_save(copy_from_env)
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def verify_complete_webpage_save(copy_from_env) -> Dict[str, Any]:
    """
    Verify complete webpage save with resources.
    
    Returns:
        Verification result dict
    """
    downloads_path = "/home/ga/Downloads"
    expected_html = "demo_page.html"
    expected_folder = "demo_page_files"
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: HTML file exists
    logger.info("Checking for HTML file...")
    html_exists, html_size = check_html_file_exists(
        copy_from_env, downloads_path, expected_html
    )
    
    if html_exists:
        feedback_parts.append(f"✓ HTML file found: {expected_html} ({html_size} bytes)")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ HTML file not found: {expected_html}")
        # If HTML doesn't exist, task clearly failed
        return {
            "passed": False,
            "score": 0,
            "feedback": "\n".join(feedback_parts) + "\n\nHTML file was not saved. Did you use Ctrl+S and save the file?"
        }
    
    # Criterion 2: Resources folder exists
    logger.info("Checking for resources folder...")
    folder_exists, resource_list = check_resources_folder_exists(
        copy_from_env, downloads_path, expected_folder
    )
    
    if folder_exists:
        feedback_parts.append(f"✓ Resources folder found: {expected_folder}/")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Resources folder not found: {expected_folder}/")
    
    # Criterion 3: Minimum resource count
    logger.info("Checking resource count...")
    min_resources = 3
    resource_count = len(resource_list)
    
    if resource_count >= min_resources:
        feedback_parts.append(f"✓ Sufficient resources: {resource_count} files (minimum {min_resources})")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Insufficient resources: {resource_count} files (need at least {min_resources})")
    
    # Criterion 4: Resource types present
    logger.info("Checking resource types...")
    resource_types = categorize_resources(resource_list)
    
    has_images = resource_types['images'] >= 1
    has_css = resource_types['css'] >= 1
    has_js = resource_types['js'] >= 1
    
    if has_images and (has_css or has_js):
        feedback_parts.append(
            f"✓ Resource types detected: {resource_types['images']} images, "
            f"{resource_types['css']} CSS, {resource_types['js']} JS"
        )
        criteria_met += 1
    else:
        feedback_parts.append(
            f"✗ Missing resource types: {resource_types['images']} images, "
            f"{resource_types['css']} CSS, {resource_types['js']} JS"
        )
    
    # Criterion 5: HTML file has reasonable size
    logger.info("Checking HTML file size...")
    html_size_ok = html_size > 500  # At least 500 bytes
    
    if html_size_ok:
        feedback_parts.append(f"✓ HTML file size reasonable: {html_size} bytes")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ HTML file too small: {html_size} bytes (possibly incomplete)")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need 4/5 criteria (80%)
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    
    if passed:
        feedback += "\n✅ Task PASSED: Complete webpage save successful!"
    else:
        feedback += "\n❌ Task FAILED: Incomplete save or missing resources"
        feedback += "\n\nTip: Use Ctrl+S → Select 'Webpage, Complete' format → Save"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "html_exists": html_exists,
            "html_size": html_size,
            "folder_exists": folder_exists,
            "resource_count": resource_count,
            "resource_types": resource_types,
            "criteria_met": criteria_met
        }
    }


def check_html_file_exists(copy_from_env, downloads_path: str, filename: str) -> Tuple[bool, int]:
    """
    Check if HTML file exists and get its size.
    
    Returns:
        Tuple of (exists: bool, size: int)
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.html')
        temp_file.close()
        
        container_path = f"{downloads_path}/{filename}"
        logger.info(f"Trying to copy HTML from: {container_path}")
        
        copy_from_env(container_path, temp_file.name)
        
        if Path(temp_file.name).exists():
            size = Path(temp_file.name).stat().st_size
            os.unlink(temp_file.name)
            
            if size > 0:
                logger.info(f"✓ HTML file found, size: {size} bytes")
                return True, size
        
        os.unlink(temp_file.name)
        return False, 0
        
    except Exception as e:
        logger.warning(f"HTML file check failed: {e}")
        return False, 0


def check_resources_folder_exists(copy_from_env, downloads_path: str, folder_name: str) -> Tuple[bool, List[str]]:
    """
    Check if resources folder exists and list its contents.
    
    Returns:
        Tuple of (exists: bool, file_list: List[str])
    """
    try:
        # Try to copy a known resource file to verify folder exists
        # We'll try to list files by attempting to copy them
        
        # Common resource filenames from our test page
        test_files = [
            "style.css",
            "script.js",
            "image1.jpg",
            "image2.png",
            "image3.jpg"
        ]
        
        found_files = []
        
        for test_file in test_files:
            try:
                temp_file = tempfile.NamedTemporaryFile(delete=False)
                temp_file.close()
                
                container_path = f"{downloads_path}/{folder_name}/{test_file}"
                copy_from_env(container_path, temp_file.name)
                
                if Path(temp_file.name).stat().st_size > 0:
                    found_files.append(test_file)
                    logger.info(f"✓ Found resource: {test_file}")
                
                os.unlink(temp_file.name)
                
            except Exception as e:
                logger.debug(f"Resource {test_file} not found: {e}")
                if Path(temp_file.name).exists():
                    os.unlink(temp_file.name)
                continue
        
        if len(found_files) > 0:
            logger.info(f"✓ Resources folder exists with {len(found_files)} files")
            return True, found_files
        else:
            logger.warning("Resources folder appears to be empty or not exist")
            return False, []
            
    except Exception as e:
        logger.error(f"Error checking resources folder: {e}")
        return False, []


def categorize_resources(resource_list: List[str]) -> Dict[str, int]:
    """
    Categorize resources by file type.
    
    Returns:
        Dict with counts for 'images', 'css', 'js', 'other'
    """
    categories = {
        'images': 0,
        'css': 0,
        'js': 0,
        'other': 0
    }
    
    for filename in resource_list:
        ext = Path(filename).suffix.lower()
        
        if ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.svg', '.bmp']:
            categories['images'] += 1
        elif ext == '.css':
            categories['css'] += 1
        elif ext == '.js':
            categories['js'] += 1
        else:
            categories['other'] += 1
    
    return categories
