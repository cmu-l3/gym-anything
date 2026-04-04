#!/usr/bin/env python3
"""
Verifier for Chrome Save Webpage Complete Task: save_page_complete@1
Task: Save Wikipedia Web Archiving article as complete webpage with all resources

Verification Strategy:
- Check HTML file exists in Downloads folder (≥50KB)
- Check resources folder exists with correct naming convention
- Verify HTML content has proper structure and references
- Count and validate resource files (CSS ≥2, images ≥5, JS files present)
- Ensure total resource count is adequate (≥15 files)
- Validate HTML contains expected content keywords
"""

import logging
import sys
import os
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import HTML parsing libraries
try:
    from bs4 import BeautifulSoup
    HAS_BS4 = True
except ImportError:
    HAS_BS4 = False
    logger.warning("BeautifulSoup not available, HTML content verification will be limited")

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available")
    def cleanup_verification_temp():
        pass


# Task configuration
DOWNLOADS_PATH = "/home/ga/Downloads"
EXPECTED_FILENAME = "web_archiving_complete"
EXPECTED_HTML = f"{EXPECTED_FILENAME}.html"
EXPECTED_FOLDER = f"{EXPECTED_FILENAME}_files"


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for save_page_complete@1 task.
    
    Verifies that the Wikipedia article was saved with complete resources.
    
    Scoring criteria (8 total, need 6+ to pass at 75%):
    1. HTML file exists
    2. HTML file has adequate size (≥50KB)
    3. Resources folder exists
    4. Resources folder follows naming convention
    5. Adequate CSS files (≥2)
    6. Adequate image files (≥5)
    7. Total resource count adequate (≥15)
    8. HTML content valid (proper structure, references, keywords)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Initialize results tracking
        results = {
            "html_exists": False,
            "html_size_ok": False,
            "folder_exists": False,
            "naming_correct": False,
            "has_css": False,
            "has_images": False,
            "resource_count_ok": False,
            "html_content_ok": False
        }
        
        feedback_parts = []
        
        # Criterion 1 & 2: Check HTML file exists and size
        html_exists, html_size, html_path, html_feedback = check_html_file(copy_from_env)
        results["html_exists"] = html_exists
        results["html_size_ok"] = html_size >= 50 * 1024 if html_exists else False
        feedback_parts.append(html_feedback)
        
        if not html_exists:
            # Early exit if HTML doesn't exist
            return build_result(results, feedback_parts)
        
        # Criterion 3 & 4: Check resources folder
        folder_info = check_resources_folder(copy_from_env)
        results["folder_exists"] = folder_info["exists"]
        results["naming_correct"] = folder_info["exists"]  # If it exists, naming must be correct
        
        if folder_info["exists"]:
            feedback_parts.append(
                f"✓ Resources folder exists: {folder_info['file_count']} files "
                f"({folder_info['css_count']} CSS, {folder_info['img_count']} images, "
                f"{folder_info['js_count']} JS)"
            )
            
            # Criterion 5: CSS files
            results["has_css"] = folder_info["css_count"] >= 2
            if not results["has_css"]:
                feedback_parts.append(f"✗ Insufficient CSS files ({folder_info['css_count']}, expected ≥2)")
            
            # Criterion 6: Image files
            results["has_images"] = folder_info["img_count"] >= 5
            if not results["has_images"]:
                feedback_parts.append(f"✗ Insufficient images ({folder_info['img_count']}, expected ≥5)")
            
            # Criterion 7: Total resource count
            results["resource_count_ok"] = folder_info["file_count"] >= 15
            if not results["resource_count_ok"]:
                feedback_parts.append(f"✗ Insufficient total resources ({folder_info['file_count']}, expected ≥15)")
        else:
            feedback_parts.append("✗ Resources folder not found - may have used wrong save format")
        
        # Criterion 8: HTML content validation
        if html_exists and html_path:
            content_ok, content_feedback = verify_html_content(html_path)
            results["html_content_ok"] = content_ok
            feedback_parts.append(content_feedback)
        
        # Build final result
        return build_result(results, feedback_parts)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def check_html_file(copy_from_env) -> Tuple[bool, int, Optional[str], str]:
    """
    Check if HTML file exists and copy it for further analysis.
    
    Returns:
        Tuple of (exists, size_bytes, local_path, feedback)
    """
    container_path = f"{DOWNLOADS_PATH}/{EXPECTED_HTML}"
    
    try:
        # Create temporary file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.html')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try to copy HTML file
        logger.info(f"Attempting to copy HTML from: {container_path}")
        copy_from_env(container_path, temp_path)
        
        # Check if file was copied successfully
        if not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
            os.unlink(temp_path) if os.path.exists(temp_path) else None
            return False, 0, None, "✗ HTML file not found in Downloads folder"
        
        size = os.path.getsize(temp_path)
        size_kb = size / 1024
        
        if size < 50 * 1024:
            feedback = f"✗ HTML file too small ({size_kb:.1f}KB, expected ≥50KB)"
        else:
            feedback = f"✓ HTML file exists ({size_kb:.1f}KB)"
        
        return True, size, temp_path, feedback
        
    except Exception as e:
        logger.error(f"Error checking HTML file: {e}")
        return False, 0, None, f"✗ HTML file not found: {str(e)}"


def check_resources_folder(copy_from_env) -> Dict[str, Any]:
    """
    Check if resources folder exists and analyze its contents.
    
    Returns:
        Dict with exists, file_count, css_count, img_count, js_count, total_size
    """
    result = {
        "exists": False,
        "file_count": 0,
        "css_count": 0,
        "img_count": 0,
        "js_count": 0,
        "total_size": 0
    }
    
    # We need to check if the folder exists by trying to copy a verification file
    # or by examining the directory listing
    
    # Strategy: Try to copy the verification info file that lists the folder
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/save_complete_verification.txt", temp_path)
        
        with open(temp_path, 'r') as f:
            content = f.read()
        
        os.unlink(temp_path)
        
        # Parse the verification file to extract counts
        if "Resources folder found" in content:
            result["exists"] = True
            
            # Extract counts using string parsing
            for line in content.split('\n'):
                if "CSS files:" in line:
                    try:
                        result["css_count"] = int(line.split(':')[1].strip())
                    except:
                        pass
                elif "Image files:" in line:
                    try:
                        result["img_count"] = int(line.split(':')[1].strip())
                    except:
                        pass
                elif "JavaScript files:" in line:
                    try:
                        result["js_count"] = int(line.split(':')[1].strip())
                    except:
                        pass
                elif "Resources folder found" in line:
                    # Try to extract file count from format: "...files/ (N files, ...)"
                    try:
                        count_part = line.split('(')[1].split('files')[0].strip()
                        result["file_count"] = int(count_part)
                    except:
                        pass
        
        logger.info(f"Resources folder analysis: {result}")
        return result
        
    except Exception as e:
        logger.warning(f"Could not read verification file, trying direct approach: {e}")
    
    # Fallback: Try to list directory contents using a different approach
    # We can't directly list directories, so we rely on the export script's verification
    
    return result


def verify_html_content(html_path: str) -> Tuple[bool, str]:
    """
    Verify HTML content has proper structure and references.
    
    Checks:
    - Has proper HTML structure (html, head, body tags)
    - Contains "web archiving" text
    - Has local resource references (_files/ in src/href)
    - Has images and links
    
    Returns:
        Tuple of (is_valid, feedback)
    """
    if not HAS_BS4:
        # Fallback: Basic text analysis
        try:
            with open(html_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            has_html = '<html' in content.lower()
            has_body = '<body' in content.lower()
            has_content = 'web archiving' in content.lower()
            has_refs = f'{EXPECTED_FILENAME}_files/' in content
            
            if has_html and has_body and has_content and has_refs:
                return True, "✓ HTML content valid (basic check)"
            else:
                issues = []
                if not has_refs:
                    issues.append("no local resource references")
                if not has_content:
                    issues.append("missing expected content")
                return False, f"✗ HTML content issues: {', '.join(issues)}"
        except Exception as e:
            return False, f"✗ Error reading HTML: {str(e)}"
    
    # Full verification with BeautifulSoup
    try:
        with open(html_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        soup = BeautifulSoup(content, 'html.parser')
        
        # Check structure
        has_title = soup.find('title') is not None
        has_body = soup.find('body') is not None
        
        # Check content
        contains_keyword = 'web archiving' in content.lower()
        
        # Check for local references
        has_local_refs = f'{EXPECTED_FILENAME}_files/' in content
        
        # Count elements
        img_count = len(soup.find_all('img'))
        link_count = len(soup.find_all('link', rel='stylesheet'))
        
        # Validate
        if has_title and has_body and contains_keyword and has_local_refs and img_count > 0:
            title_text = soup.find('title').text[:50] if has_title else ""
            return True, f"✓ HTML content valid (title: '{title_text}...', {img_count} images, {link_count} stylesheets)"
        else:
            issues = []
            if not has_local_refs:
                issues.append("no local resource references")
            if img_count == 0:
                issues.append("no images")
            if not contains_keyword:
                issues.append("missing 'web archiving' content")
            return False, f"✗ HTML content issues: {', '.join(issues)}"
    
    except Exception as e:
        logger.error(f"Error parsing HTML: {e}")
        return False, f"✗ Error parsing HTML: {str(e)}"


def build_result(results: Dict[str, bool], feedback_parts: List[str]) -> Dict[str, Any]:
    """
    Build final verification result with scoring.
    
    Args:
        results: Dict of boolean results for each criterion
        feedback_parts: List of feedback strings
        
    Returns:
        Dict with passed, score, feedback, details
    """
    # Calculate score
    criteria_met = sum(results.values())
    total_criteria = len(results)
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 6/8 criteria (75%)
    
    # Build feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    
    if passed:
        feedback += "\n✅ Task completed successfully!"
        feedback += "\nPage saved with complete resources (HTML + folder)."
    else:
        feedback += "\n❌ Task incomplete or incorrect format used."
        if not results["folder_exists"]:
            feedback += "\n\n💡 Hint: Use 'Webpage, Complete' format, not 'HTML Only'"
        if not results["html_exists"]:
            feedback += "\n💡 Hint: Ensure filename is 'web_archiving_complete'"
    
    if not HAS_BS4:
        feedback += "\n\n⚠ Note: BeautifulSoup not available, HTML content check was limited"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria_met={criteria_met}/{total_criteria}")
    
    # Clean up temp files
    cleanup_verification_temp()
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria": results,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
