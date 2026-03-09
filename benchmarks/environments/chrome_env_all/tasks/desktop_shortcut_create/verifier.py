#!/usr/bin/env python3
"""
Verifier for Chrome Desktop Shortcut Creation Task (desktop_shortcut_create@1)
Task: Create desktop shortcut for Wikipedia with custom name and window mode enabled

Verification Strategy:
- Search for .desktop files in ~/Desktop and ~/.local/share/applications
- Look for recently created files (within task timeframe)
- Parse .desktop file contents (INI format)
- Verify URL contains wikipedia.org
- Verify --app= flag is present (window mode)
- Verify Name field contains "Wiki Reference"
"""

import logging
import sys
import os
import tempfile
from pathlib import Path
from datetime import datetime, timedelta
import configparser
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_task(traj, env_info, task_info):
    """
    Main verification function for desktop_shortcut_create@1.
    
    Verifies that a desktop shortcut was created with:
    1. File exists in correct location
    2. Contains wikipedia.org URL
    3. Has --app= flag (window mode enabled)
    4. Name field shows "Wiki Reference" (custom name)
    
    Scoring:
    - 100%: All 4 criteria met (perfect)
    - 75%: 3/4 criteria met
    - 50%: 2/4 criteria met
    - 25%: 1/4 criteria met
    - 0%: No criteria met
    
    Pass threshold: 100% (all 4 criteria required for this binary task)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Find the desktop shortcut file
        shortcut_file, file_path = find_desktop_shortcut(copy_from_env)
        
        if not shortcut_file:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No desktop shortcut file found for Wikipedia.\n\nPlease create a shortcut using:\nChrome menu (⋮) → More tools → Create shortcut...\n\nMake sure to:\n- Change name to 'Wiki Reference'\n- Check 'Open as window' checkbox\n- Click Create"
            }
        
        logger.info(f"Found shortcut file: {file_path}")
        
        # Parse the .desktop file
        config = parse_desktop_file(shortcut_file)
        
        if not config:
            # Clean up temp file
            if os.path.exists(shortcut_file):
                os.unlink(shortcut_file)
            return {
                "passed": False,
                "score": 25,
                "feedback": "Desktop shortcut file found but could not be parsed. File may be corrupted or in wrong format."
            }
        
        # Verify all criteria
        criteria_results = verify_shortcut_criteria(config, file_path)
        
        # Clean up temp file
        if os.path.exists(shortcut_file):
            os.unlink(shortcut_file)
        
        return criteria_results
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def find_desktop_shortcut(copy_from_env):
    """
    Find and copy the desktop shortcut file from container.
    
    Searches in:
    - ~/Desktop/
    - ~/.local/share/applications/
    
    Looks for files containing "wiki" in filename or Chrome-generated shortcut files.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (local_temp_path: str or None, container_path: str or None)
    """
    # Define search locations
    search_locations = [
        "/home/ga/Desktop",
        "/home/ga/.local/share/applications"
    ]
    
    # Try to get task start time for filtering
    task_start_time = None
    try:
        temp_time = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_time.close()
        copy_from_env("/tmp/task_start_time.txt", temp_time.name)
        with open(temp_time.name, 'r') as f:
            task_start_time = int(f.read().strip())
        os.unlink(temp_time.name)
        logger.info(f"Task start time: {task_start_time}")
    except Exception as e:
        logger.warning(f"Could not get task start time: {e}")
        task_start_time = int((datetime.now() - timedelta(minutes=5)).timestamp())
    
    # Try common filename patterns for Wikipedia shortcuts
    filename_patterns = [
        # User-specified names
        "wiki-reference",
        "Wiki-Reference", 
        "wiki_reference",
        "Wiki_Reference",
        "wiki reference",
        "Wiki Reference",
        # Default Wikipedia names
        "wikipedia",
        "Wikipedia",
        # Chrome-generated names
        "chrome-wikipedia",
        "chrome-www_wikipedia_org-Default",
        "chrome-www.wikipedia.org-Default",
        "chrome-wikipedia.org-Default",
    ]
    
    for location in search_locations:
        logger.info(f"Searching in: {location}")
        
        for pattern in filename_patterns:
            # Try with .desktop extension
            container_path = f"{location}/{pattern}.desktop"
            
            try:
                temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.desktop')
                temp_path = temp_file.name
                temp_file.close()
                
                logger.debug(f"Trying to copy: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    # Verify it's a valid .desktop file with wikipedia
                    with open(temp_path, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read()
                        if '[Desktop Entry]' in content and 'wikipedia' in content.lower():
                            logger.info(f"✓ Found valid shortcut at: {container_path}")
                            return temp_path, container_path
                
                # Not the right file, clean up
                os.unlink(temp_path)
                
            except Exception as e:
                logger.debug(f"Could not copy {container_path}: {e}")
                if 'temp_path' in locals() and os.path.exists(temp_path):
                    try:
                        os.unlink(temp_path)
                    except:
                        pass
                continue
    
    # If no file found with expected patterns, try Chrome's webapp naming pattern
    logger.info("No file found with expected names, trying Chrome webapp patterns...")
    
    # Chrome often creates webapp shortcuts with hash-based names
    for location in search_locations:
        for prefix in ["chrome-", "webapp-", ""]:
            for i in range(1, 50):
                container_path = f"{location}/{prefix}wikipedia{i}.desktop" if prefix else f"{location}/wikipedia-{i}.desktop"
                
                try:
                    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.desktop')
                    temp_path = temp_file.name
                    temp_file.close()
                    
                    copy_from_env(container_path, temp_path)
                    
                    if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                        with open(temp_path, 'r', encoding='utf-8', errors='ignore') as f:
                            content = f.read()
                            if '[Desktop Entry]' in content and 'wikipedia' in content.lower():
                                logger.info(f"✓ Found shortcut at: {container_path}")
                                return temp_path, container_path
                    
                    os.unlink(temp_path)
                except:
                    if 'temp_path' in locals() and os.path.exists(temp_path):
                        try:
                            os.unlink(temp_path)
                        except:
                            pass
                    continue
    
    logger.warning("No desktop shortcut file found for Wikipedia")
    return None, None


def parse_desktop_file(file_path):
    """
    Parse .desktop file and extract configuration.
    
    .desktop files follow the INI format with [Desktop Entry] section.
    
    Args:
        file_path: Path to .desktop file
        
    Returns:
        Dict with configuration values, or None if parsing failed
    """
    try:
        # Try using configparser
        config = configparser.ConfigParser()
        config.read(file_path, encoding='utf-8')
        
        if 'Desktop Entry' in config:
            return dict(config['Desktop Entry'])
        else:
            logger.warning("No [Desktop Entry] section found, trying manual parsing")
    except Exception as e:
        logger.warning(f"ConfigParser failed: {e}, trying manual parsing")
    
    # Fallback: Manual parsing for non-standard .desktop files
    try:
        result = {}
        in_desktop_entry = False
        
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                
                if line == '[Desktop Entry]':
                    in_desktop_entry = True
                    continue
                
                if line.startswith('[') and line.endswith(']'):
                    # New section, stop if we were in Desktop Entry
                    if in_desktop_entry:
                        break
                    continue
                
                if in_desktop_entry and line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    result[key.strip()] = value.strip()
        
        if result:
            return result
        else:
            logger.error("Could not parse .desktop file - no content found")
            return None
            
    except Exception as e:
        logger.error(f"Manual parsing failed: {e}")
        return None


def verify_shortcut_criteria(config, file_path):
    """
    Verify all criteria for the desktop shortcut.
    
    Criteria:
    1. File exists (already confirmed)
    2. URL contains wikipedia.org
    3. Window mode enabled (--app= flag)
    4. Custom name "Wiki Reference"
    
    Args:
        config: Dict of .desktop file configuration
        file_path: Path to the file (for logging)
        
    Returns:
        Dict with passed, score, feedback, details
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: File exists (already met if we got here)
    criteria_met += 1
    feedback_parts.append("✓ Desktop shortcut file created")
    
    # Extract key fields
    exec_line = config.get('Exec', '')
    name = config.get('Name', '')
    type_field = config.get('Type', '')
    
    logger.info(f"Exec: {exec_line}")
    logger.info(f"Name: {name}")
    logger.info(f"Type: {type_field}")
    
    # Criterion 2: URL contains wikipedia.org
    url_correct = 'wikipedia.org' in exec_line.lower()
    if url_correct:
        criteria_met += 1
        feedback_parts.append("✓ Shortcut URL contains wikipedia.org")
    else:
        feedback_parts.append(f"✗ Shortcut URL does not contain wikipedia.org (found: {exec_line[:80]}...)")
    
    # Criterion 3: Window mode enabled (--app= flag)
    window_mode = '--app=' in exec_line
    if window_mode:
        criteria_met += 1
        feedback_parts.append("✓ Window mode enabled (--app= flag present)")
    else:
        feedback_parts.append("✗ Window mode not enabled (missing --app= flag in Exec command)")
    
    # Criterion 4: Custom name "Wiki Reference"
    # Be flexible with exact matching (case-insensitive, handle variations)
    name_lower = name.lower()
    custom_name = 'wiki reference' in name_lower or 'wiki-reference' in name_lower or 'wiki_reference' in name_lower
    if custom_name:
        criteria_met += 1
        feedback_parts.append(f"✓ Custom name applied: '{name}'")
    else:
        feedback_parts.append(f"✗ Name is '{name}', expected 'Wiki Reference'")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = criteria_met == total_criteria  # All criteria must be met
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not passed:
        feedback += "\n\n"
        if criteria_met >= 3:
            feedback += "Almost there! Review the failed criterion above."
        else:
            feedback += "To create the shortcut correctly:\n"
            feedback += "1. Navigate to https://www.wikipedia.org/\n"
            feedback += "2. Click Chrome menu (⋮) in top-right\n"
            feedback += "3. Select: More tools → Create shortcut...\n"
            feedback += "4. Change name to 'Wiki Reference'\n"
            feedback += "5. Check 'Open as window' checkbox\n"
            feedback += "6. Click Create button"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "file_path": file_path,
            "name_used": name,
            "exec_command": exec_line[:100] + "..." if len(exec_line) > 100 else exec_line,
            "has_url": url_correct,
            "has_window_mode": window_mode,
            "has_custom_name": custom_name,
            "criteria_met": criteria_met
        }
    }
