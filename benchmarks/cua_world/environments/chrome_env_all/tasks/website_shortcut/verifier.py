#!/usr/bin/env python3
"""
Verifier for Chrome Website Shortcut Creation Task (website_shortcut@1)
Task: Create a desktop shortcut for Wikipedia with 'Open as window' option

Verification Strategy:
- Scan /home/ga/Desktop/ for .desktop files
- Parse freedesktop.org .desktop entry format
- Verify Name field matches expected shortcut name
- Verify Exec field contains correct URL
- Verify --app= flag is present for "Open as window" mode
- Validate desktop entry format compliance
"""

import logging
import sys
import os
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path (though we won't use Chrome utils for this task)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))


def parse_desktop_entry(desktop_file_path: str) -> Dict[str, str]:
    """
    Parse a .desktop file following freedesktop.org specification.
    
    Args:
        desktop_file_path: Path to .desktop file
        
    Returns:
        Dictionary with parsed key-value pairs
    """
    entry = {}
    
    try:
        with open(desktop_file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        in_desktop_entry_section = False
        
        for line in lines:
            line = line.strip()
            
            # Skip empty lines and comments
            if not line or line.startswith('#'):
                continue
            
            # Check for section headers
            if line.startswith('[') and line.endswith(']'):
                section = line[1:-1]
                in_desktop_entry_section = (section == 'Desktop Entry')
                continue
            
            # Parse key=value pairs only in [Desktop Entry] section
            if in_desktop_entry_section and '=' in line:
                key, value = line.split('=', 1)
                entry[key.strip()] = value.strip()
        
        return entry
        
    except Exception as e:
        logger.error(f"Error parsing desktop file {desktop_file_path}: {e}")
        return {}


def find_desktop_files(copy_from_env) -> Tuple[bool, List[Tuple[str, str]], str]:
    """
    Find and copy all .desktop files from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (success, [(filename, local_path), ...], error_message)
    """
    try:
        # First, get the list of desktop files
        temp_list = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_list_path = temp_list.name
        temp_list.close()
        
        try:
            copy_from_env("/tmp/desktop_files_list.txt", temp_list_path)
            
            with open(temp_list_path, 'r') as f:
                file_list_content = f.read().strip()
            
            os.unlink(temp_list_path)
            
            if file_list_content in ["none", "error", ""]:
                return False, [], "No .desktop files found on desktop"
                
            filenames = [line.strip() for line in file_list_content.split('\n') if line.strip()]
            
        except Exception as e:
            logger.warning(f"Could not read desktop_files_list.txt: {e}, trying direct scan")
            os.unlink(temp_list_path)
            filenames = None
        
        # Try to copy .desktop files from various locations
        desktop_files = []
        
        # If we have a file list, try to copy each file
        if filenames:
            for filename in filenames:
                temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.desktop', mode='wb')
                temp_path = temp_file.name
                temp_file.close()
                
                container_paths = [
                    f"/tmp/shortcut_verification/{filename}",
                    f"/tmp/{filename}",
                    f"/home/ga/Desktop/{filename}",
                    f"/tmp/desktop_backup/{filename}"
                ]
                
                copied = False
                for container_path in container_paths:
                    try:
                        copy_from_env(container_path, temp_path)
                        
                        if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                            logger.info(f"✓ Successfully copied: {filename} from {container_path}")
                            desktop_files.append((filename, temp_path))
                            copied = True
                            break
                    except Exception as e:
                        logger.debug(f"Failed to copy from {container_path}: {e}")
                        continue
                
                if not copied:
                    os.unlink(temp_path)
        
        # Fallback: Try to find any .desktop file with common patterns
        if not desktop_files:
            logger.info("Trying fallback search for .desktop files...")
            
            # Try common Wikipedia shortcut naming patterns
            possible_names = [
                "Wikipedia.desktop",
                "wikipedia.desktop",
                "en.wikipedia.org.desktop",
                "Wikipedia_en.wikipedia.org.desktop"
            ]
            
            for filename in possible_names:
                temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.desktop', mode='wb')
                temp_path = temp_file.name
                temp_file.close()
                
                container_paths = [
                    f"/home/ga/Desktop/{filename}",
                    f"/tmp/desktop_backup/{filename}",
                    f"/tmp/{filename}"
                ]
                
                for container_path in container_paths:
                    try:
                        copy_from_env(container_path, temp_path)
                        
                        if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                            logger.info(f"✓ Found via fallback: {filename}")
                            desktop_files.append((filename, temp_path))
                            break
                    except:
                        continue
                
                if not desktop_files:
                    os.unlink(temp_path)
                else:
                    break
        
        if not desktop_files:
            return False, [], "Could not find or copy any .desktop files"
        
        return True, desktop_files, ""
        
    except Exception as e:
        logger.error(f"Error finding desktop files: {e}", exc_info=True)
        return False, [], f"Error: {str(e)}"


def normalize_url(url: str) -> str:
    """Normalize URL for comparison"""
    if not url:
        return ""
    # Remove trailing slashes
    url = url.rstrip('/')
    # Convert to lowercase
    url = url.lower()
    # Remove protocol prefix for comparison
    url = re.sub(r'^https?://', '', url)
    return url


def extract_url_from_exec(exec_line: str) -> Optional[str]:
    """
    Extract URL from Exec line in .desktop file.
    
    Args:
        exec_line: Value of Exec key (e.g., "/usr/bin/google-chrome-stable --app=https://en.wikipedia.org/")
        
    Returns:
        Extracted URL or None
    """
    # Look for --app= flag
    app_match = re.search(r'--app[=\s]+["\']?([^\s"\']+)["\']?', exec_line)
    if app_match:
        return app_match.group(1)
    
    # Look for any URL pattern
    url_match = re.search(r'https?://[^\s"\']+', exec_line)
    if url_match:
        return url_match.group(0)
    
    return None


def check_app_mode(exec_line: str) -> bool:
    """Check if --app= flag is present in Exec line"""
    return '--app=' in exec_line or '--app ' in exec_line


def verify_desktop_shortcut(
    desktop_entry: Dict[str, str],
    filename: str,
    expected_name: str = "Wikipedia",
    expected_url: str = "https://en.wikipedia.org/",
    require_app_mode: bool = True
) -> Tuple[int, Dict[str, bool], str]:
    """
    Verify a desktop entry against expected criteria.
    
    Args:
        desktop_entry: Parsed .desktop file contents
        filename: Name of the .desktop file
        expected_name: Expected Name field value
        expected_url: Expected URL in Exec field
        require_app_mode: Whether --app= flag is required
        
    Returns:
        Tuple of (score, criteria_dict, feedback)
    """
    criteria = {
        "file_exists": True,  # If we're here, file exists
        "valid_format": False,
        "correct_name": False,
        "correct_url": False,
        "app_mode": False,
        "executable_type": False
    }
    
    feedback_parts = []
    
    # Criterion 1: Valid desktop entry format
    if desktop_entry.get('Type') and desktop_entry.get('Name') and desktop_entry.get('Exec'):
        criteria["valid_format"] = True
        feedback_parts.append("✓ Valid .desktop entry format")
    else:
        feedback_parts.append("✗ Invalid .desktop entry format (missing required fields)")
        return 0, criteria, "\n".join(feedback_parts)
    
    # Criterion 2: Correct Type
    if desktop_entry.get('Type') == 'Application':
        criteria["executable_type"] = True
        feedback_parts.append("✓ Type is 'Application'")
    else:
        feedback_parts.append(f"✗ Type is '{desktop_entry.get('Type')}' (expected 'Application')")
    
    # Criterion 3: Name matches (case-insensitive with flexibility)
    actual_name = desktop_entry.get('Name', '')
    name_lower = actual_name.lower()
    expected_lower = expected_name.lower()
    
    if name_lower == expected_lower:
        criteria["correct_name"] = True
        feedback_parts.append(f"✓ Name matches: '{actual_name}'")
    elif expected_lower in name_lower or name_lower in expected_lower:
        criteria["correct_name"] = True
        feedback_parts.append(f"✓ Name close enough: '{actual_name}' (expected '{expected_name}')")
    else:
        feedback_parts.append(f"✗ Name mismatch: '{actual_name}' (expected '{expected_name}')")
    
    # Criterion 4: URL matches
    exec_line = desktop_entry.get('Exec', '')
    actual_url = extract_url_from_exec(exec_line)
    
    if actual_url:
        normalized_actual = normalize_url(actual_url)
        normalized_expected = normalize_url(expected_url)
        
        if normalized_actual == normalized_expected:
            criteria["correct_url"] = True
            feedback_parts.append(f"✓ URL matches: {actual_url}")
        elif "wikipedia.org" in normalized_actual:
            criteria["correct_url"] = True
            feedback_parts.append(f"✓ URL is Wikipedia: {actual_url}")
        else:
            feedback_parts.append(f"✗ URL mismatch: {actual_url} (expected {expected_url})")
    else:
        feedback_parts.append(f"✗ Could not extract URL from Exec line: {exec_line}")
    
    # Criterion 5: App mode (--app= flag)
    has_app_mode = check_app_mode(exec_line)
    
    if has_app_mode:
        criteria["app_mode"] = True
        feedback_parts.append("✓ 'Open as window' mode enabled (--app= flag present)")
    else:
        if require_app_mode:
            feedback_parts.append("✗ 'Open as window' mode not enabled (missing --app= flag)")
        else:
            feedback_parts.append("⚠ 'Open as window' mode not enabled (optional)")
            criteria["app_mode"] = True  # Don't penalize if not required
    
    # Calculate score
    total_criteria = len(criteria)
    criteria_met = sum(criteria.values())
    score = int((criteria_met / total_criteria) * 100)
    
    feedback = "\n".join(feedback_parts)
    
    return score, criteria, feedback


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for website_shortcut@1.
    
    Verifies:
    1. .desktop file exists on desktop
    2. Valid .desktop entry format
    3. Name field matches "Wikipedia" (or similar)
    4. Exec field contains correct Wikipedia URL
    5. --app= flag present for "Open as window" mode
    6. Type is 'Application'
    
    Scoring:
    - 100%: All 6 criteria met (perfect execution)
    - 85-99%: 5/6 criteria met (minor issue)
    - 70-84%: 4/6 criteria met (acceptable)
    - 50-69%: 3/6 criteria met (significant issues)
    - <50%: <3 criteria met (task failed)
    
    Pass threshold: 75% (requires at least 4-5 out of 6 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    try:
        # Task parameters
        expected_name = task_info.get("shortcut_name", "Wikipedia")
        expected_url = task_info.get("target_url", "https://en.wikipedia.org/")
        require_app_mode = task_info.get("app_mode", True)
        
        logger.info(f"Verifying shortcut: name='{expected_name}', url='{expected_url}', app_mode={require_app_mode}")
        
        # Find and copy desktop files
        success, desktop_files, error = find_desktop_files(copy_from_env)
        
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"✗ No desktop shortcut found\n{error}\n\nExpected: .desktop file in /home/ga/Desktop/ with shortcut to Wikipedia"
            }
        
        logger.info(f"Found {len(desktop_files)} .desktop file(s)")
        
        # Verify each desktop file and find the best match
        best_score = 0
        best_feedback = ""
        best_criteria = {}
        best_filename = ""
        
        for filename, local_path in desktop_files:
            logger.info(f"Verifying: {filename}")
            
            # Parse desktop entry
            desktop_entry = parse_desktop_entry(local_path)
            
            if not desktop_entry:
                logger.warning(f"Could not parse {filename}")
                continue
            
            # Verify this desktop file
            score, criteria, feedback = verify_desktop_shortcut(
                desktop_entry,
                filename,
                expected_name,
                expected_url,
                require_app_mode
            )
            
            logger.info(f"Score for {filename}: {score}")
            
            if score > best_score:
                best_score = score
                best_feedback = feedback
                best_criteria = criteria
                best_filename = filename
        
        # Clean up temporary files
        for _, local_path in desktop_files:
            try:
                os.unlink(local_path)
            except:
                pass
        
        if best_score == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "✗ Found .desktop file(s) but could not verify any as valid shortcut"
            }
        
        # Build final feedback
        passed = best_score >= 75
        
        final_feedback = f"Desktop Shortcut Verification: {best_filename}\n"
        final_feedback += "=" * 60 + "\n"
        final_feedback += best_feedback + "\n"
        final_feedback += "=" * 60 + "\n"
        final_feedback += f"Criteria met: {sum(best_criteria.values())}/{len(best_criteria)}\n"
        final_feedback += f"Final score: {best_score}%\n"
        final_feedback += f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}"
        
        logger.info(f"Verification complete: passed={passed}, score={best_score}")
        
        return {
            "passed": passed,
            "score": best_score,
            "feedback": final_feedback,
            "details": {
                "filename": best_filename,
                "criteria": best_criteria,
                "criteria_met": sum(best_criteria.values()),
                "total_criteria": len(best_criteria)
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
