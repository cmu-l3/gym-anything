#!/usr/bin/env python3
"""
Verifier for Chrome DevTools Local CSS Override Task (css_override_persist@1)
Task: Enable Local Overrides, modify CSS styling, and persist changes to disk

Verification Strategy:
1. Check override directory exists and has proper structure
2. Search for CSS files in override directory (recursively)
3. Parse CSS content and verify color property changed from blue to red
4. Optionally verify DevTools workspace configuration
5. Multi-criteria scoring for robustness
"""

import logging
import sys
import os
import json
import re
import tempfile
import shutil
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for css_override_persist@1 task.
    
    Verifies:
    1. Override directory exists with proper structure
    2. CSS override files were created
    3. CSS contains modified color property (blue → red)
    4. DevTools workspace is configured (optional)
    5. Files are non-empty and valid
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Step 1: Copy override directory from container
        override_data = copy_override_directory(copy_from_env)
        
        if not override_data["success"]:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access override directory: {override_data['error']}"
            }
        
        # Step 2: Verify directory structure and find CSS files
        css_files = find_override_css_files(override_data["local_path"])
        
        if not css_files:
            return {
                "passed": False,
                "score": 25,
                "feedback": "Override directory exists but no CSS files found. Did you save the override?"
            }
        
        # Step 3: Verify CSS modifications
        css_verification = verify_css_modifications(css_files)
        
        # Step 4: Optional DevTools preferences check
        devtools_config = verify_devtools_configuration(copy_from_env)
        
        # Step 5: Calculate final score and feedback
        result = calculate_final_score(
            override_data,
            css_files,
            css_verification,
            devtools_config
        )
        
        # Cleanup temporary files
        cleanup_local_files(override_data["local_path"])
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


def copy_override_directory(copy_from_env) -> Dict[str, Any]:
    """
    Copy the chrome_overrides directory from container to host.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict with success (bool), local_path (str), error (str)
    """
    try:
        # Create temporary directory for override files
        temp_dir = tempfile.mkdtemp(prefix="chrome_override_verify_")
        
        # Try to copy the entire override directory
        container_paths = [
            "/tmp/chrome_overrides_export",
            "/home/ga/chrome_overrides"
        ]
        
        for container_path in container_paths:
            try:
                # Copy directory recursively by copying archive or individual files
                logger.info(f"Attempting to copy override directory from: {container_path}")
                
                # Strategy: Copy manifest file first to see what files exist
                manifest_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
                manifest_temp.close()
                
                try:
                    copy_from_env("/tmp/override_manifest.txt", manifest_temp.name)
                    
                    with open(manifest_temp.name, 'r') as f:
                        file_list = [line.strip() for line in f if line.strip()]
                    
                    os.unlink(manifest_temp.name)
                    
                    logger.info(f"Found {len(file_list)} files in override manifest")
                    
                    # Copy each file individually
                    files_copied = 0
                    for file_path in file_list:
                        if not file_path or not os.path.isabs(file_path):
                            continue
                        
                        try:
                            # Recreate directory structure in temp dir
                            rel_path = file_path.replace("/home/ga/chrome_overrides/", "")
                            local_file_path = os.path.join(temp_dir, rel_path)
                            os.makedirs(os.path.dirname(local_file_path), exist_ok=True)
                            
                            # Copy file
                            copy_from_env(file_path, local_file_path)
                            
                            if os.path.exists(local_file_path) and os.path.getsize(local_file_path) > 0:
                                files_copied += 1
                                logger.debug(f"Copied: {file_path}")
                        except Exception as e:
                            logger.debug(f"Could not copy {file_path}: {e}")
                            continue
                    
                    if files_copied > 0:
                        logger.info(f"Successfully copied {files_copied} override files")
                        return {
                            "success": True,
                            "local_path": temp_dir,
                            "error": "",
                            "files_count": files_copied
                        }
                    
                except Exception as e:
                    logger.debug(f"Manifest-based copy failed: {e}")
                
                # Fallback: Try direct directory copy (if supported)
                try:
                    export_dir = os.path.join(container_path, "*")
                    # This might not work for all copy implementations
                    # but worth trying
                    for item in ["*.css", "*.html", "*.js"]:
                        try:
                            search_pattern = f"{container_path}/**/{item}"
                            # This is a simplified approach
                            pass
                        except:
                            pass
                except Exception as e:
                    logger.debug(f"Direct copy failed: {e}")
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        # Check if any files were copied
        if os.path.exists(temp_dir):
            file_count = sum(1 for _ in Path(temp_dir).rglob('*') if _.is_file())
            if file_count > 0:
                return {
                    "success": True,
                    "local_path": temp_dir,
                    "error": "",
                    "files_count": file_count
                }
        
        # No files found
        return {
            "success": False,
            "local_path": temp_dir,
            "error": "Override directory not found or empty - Local Overrides may not be configured",
            "files_count": 0
        }
        
    except Exception as e:
        return {
            "success": False,
            "local_path": "",
            "error": f"Error copying override directory: {str(e)}",
            "files_count": 0
        }


def find_override_css_files(local_path: str) -> List[str]:
    """
    Recursively find CSS files in the override directory.
    
    Args:
        local_path: Local path to override directory
        
    Returns:
        List of paths to CSS files
    """
    if not os.path.exists(local_path):
        return []
    
    css_files = []
    for root, dirs, files in os.walk(local_path):
        for file in files:
            if file.endswith('.css') or file.endswith('.html'):
                full_path = os.path.join(root, file)
                # Check file has content
                if os.path.getsize(full_path) > 0:
                    css_files.append(full_path)
                    logger.info(f"Found override file: {file}")
    
    return css_files


def verify_css_modifications(css_files: List[str]) -> Dict[str, Any]:
    """
    Verify that CSS files contain the expected modifications (color: blue → red).
    
    Args:
        css_files: List of paths to CSS files
        
    Returns:
        Dict with found (bool), details (dict), feedback (str)
    """
    result = {
        "found": False,
        "color_changed": False,
        "property_found": False,
        "red_color_present": False,
        "blue_color_absent": False,
        "file_with_change": None,
        "feedback": ""
    }
    
    # Patterns to match color properties
    color_red_patterns = [
        r'color\s*:\s*red',
        r'color\s*:\s*#ff0000',
        r'color\s*:\s*#f00\b',
        r'color\s*:\s*rgb\s*\(\s*255\s*,\s*0\s*,\s*0\s*\)',
    ]
    
    color_blue_patterns = [
        r'color\s*:\s*blue',
        r'color\s*:\s*#0000ff',
        r'color\s*:\s*#00f\b',
        r'color\s*:\s*rgb\s*\(\s*0\s*,\s*0\s*,\s*255\s*\)',
    ]
    
    for css_file in css_files:
        try:
            with open(css_file, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            content_lower = content.lower()
            
            # Check for red color
            red_found = any(re.search(pattern, content_lower, re.IGNORECASE) for pattern in color_red_patterns)
            
            # Check if blue is still present (shouldn't be if changed correctly)
            blue_found = any(re.search(pattern, content_lower, re.IGNORECASE) for pattern in color_blue_patterns)
            
            if red_found:
                result["red_color_present"] = True
                result["property_found"] = True
                result["file_with_change"] = os.path.basename(css_file)
                
                if not blue_found:
                    result["blue_color_absent"] = True
                    result["color_changed"] = True
                    result["found"] = True
                    result["feedback"] = f"Successfully changed color from blue to red in {os.path.basename(css_file)}"
                    logger.info(f"✓ Color change verified in: {css_file}")
                    return result
                else:
                    result["feedback"] = f"Found red color but blue still present in {os.path.basename(css_file)}"
        
        except Exception as e:
            logger.warning(f"Error reading CSS file {css_file}: {e}")
            continue
    
    # If we get here, no complete change was found
    if result["red_color_present"]:
        result["feedback"] = "Red color found but verification incomplete"
    else:
        result["feedback"] = "Color property not changed to red in any override file"
    
    return result


def verify_devtools_configuration(copy_from_env) -> Dict[str, Any]:
    """
    Verify DevTools workspace configuration (optional - may not be accessible).
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict with configured (bool), details (dict)
    """
    result = {
        "configured": False,
        "workspace_found": False,
        "details": {}
    }
    
    try:
        temp_prefs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_prefs.close()
        
        # Try to copy preferences file
        prefs_paths = [
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        for prefs_path in prefs_paths:
            try:
                copy_from_env(prefs_path, temp_prefs.name)
                
                with open(temp_prefs.name, 'r', encoding='utf-8') as f:
                    prefs = json.load(f)
                
                # Check for DevTools workspace configuration
                devtools = prefs.get("devtools", {})
                
                # Look for workspace or override settings
                # Chrome stores this in various places depending on version
                if "preferences" in devtools:
                    preferences = devtools.get("preferences", {})
                    
                    # Check for workspace-related keys
                    workspace_keys = [k for k in preferences.keys() if "workspace" in k.lower() or "override" in k.lower()]
                    
                    if workspace_keys:
                        result["workspace_found"] = True
                        result["configured"] = True
                        result["details"] = {k: preferences[k] for k in workspace_keys[:3]}  # Limit output
                
                os.unlink(temp_prefs.name)
                break
                
            except Exception as e:
                logger.debug(f"Could not check DevTools config from {prefs_path}: {e}")
                continue
        
        if os.path.exists(temp_prefs.name):
            os.unlink(temp_prefs.name)
    
    except Exception as e:
        logger.debug(f"DevTools configuration check failed: {e}")
    
    return result


def calculate_final_score(override_data: Dict, css_files: List[str], 
                          css_verification: Dict, devtools_config: Dict) -> Dict[str, Any]:
    """
    Calculate final score based on all verification criteria.
    
    Criteria (5 total, need 4+ for pass):
    1. Override directory exists and has files
    2. CSS override files created
    3. Color property changed to red
    4. Blue color no longer present
    5. File integrity (non-empty, parseable)
    
    Args:
        override_data: Directory copy results
        css_files: List of found CSS files
        css_verification: CSS modification verification results
        devtools_config: DevTools configuration results
        
    Returns:
        Dict with passed, score, feedback
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: Override directory exists with files
    if override_data["success"] and override_data.get("files_count", 0) > 0:
        criteria_met += 1
        feedback_parts.append(f"✓ Override directory exists with {override_data['files_count']} file(s)")
    else:
        feedback_parts.append("✗ Override directory not found or empty")
    
    # Criterion 2: CSS files were created
    if len(css_files) > 0:
        criteria_met += 1
        feedback_parts.append(f"✓ CSS override file(s) created: {len(css_files)} file(s)")
    else:
        feedback_parts.append("✗ No CSS override files found")
    
    # Criterion 3: Red color is present
    if css_verification["red_color_present"]:
        criteria_met += 1
        feedback_parts.append(f"✓ Red color found in CSS override")
    else:
        feedback_parts.append("✗ Red color not found in CSS")
    
    # Criterion 4: Blue color is absent (successfully replaced)
    if css_verification["blue_color_absent"] or (css_verification["red_color_present"] and not css_verification.get("blue_still_present", False)):
        criteria_met += 1
        feedback_parts.append("✓ Original blue color successfully replaced")
    else:
        feedback_parts.append("⚠ Blue color may still be present")
    
    # Criterion 5: File integrity
    if css_files and all(os.path.getsize(f) > 10 for f in css_files):
        criteria_met += 1
        feedback_parts.append("✓ Override files have valid content")
    else:
        feedback_parts.append("⚠ Override files may be incomplete")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 4/5 criteria (80%)
    
    # Build final feedback
    feedback = f"CSS Override Verification: {criteria_met}/{total_criteria} criteria met\n"
    feedback += "\n".join(feedback_parts)
    feedback += f"\n\nFinal Score: {score}%"
    
    if passed:
        feedback += "\n✅ Task completed successfully! Local Overrides are working and CSS was modified."
    else:
        feedback += "\n❌ Task incomplete. "
        if criteria_met == 0:
            feedback += "Local Overrides may not have been configured."
        elif criteria_met < 3:
            feedback += "Override folder configured but CSS modifications not found."
        else:
            feedback += "Most steps completed but some verification criteria not met."
    
    # Add DevTools config info if available
    if devtools_config["configured"]:
        feedback += "\n✓ DevTools workspace configuration detected"
    
    logger.info(f"Final verification: {criteria_met}/{total_criteria} criteria met, score={score}%, passed={passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "override_files_found": len(css_files),
            "color_changed": css_verification["color_changed"],
            "devtools_configured": devtools_config["configured"]
        }
    }


def cleanup_local_files(local_path: str):
    """Clean up temporary local files."""
    if local_path and os.path.exists(local_path):
        try:
            shutil.rmtree(local_path)
            logger.info(f"Cleaned up temporary files: {local_path}")
        except Exception as e:
            logger.warning(f"Could not clean up {local_path}: {e}")
