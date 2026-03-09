"""
Verifier for undo configuration task.
Checks that the GIMP gimprc config file contains undo-levels set to 100.
"""

import os
import sys
import tempfile
import logging
from pathlib import Path

# Set up logging
logging.basicConfig(level=logging.DEBUG)


def copy_file_from_container(copy_from_env_fn, container_path, host_path):
    """Copy a file from Docker container to host using env copy utilities."""
    try:
        copy_from_env_fn(container_path, str(host_path))
        return True, ""
    except Exception as e:
        return False, f"Failed to copy {container_path}: {str(e)}"


def check_config_status(traj, env_info, task_info):
    """
    Main verifier function for undo configuration task.
    Checks if the GIMP gimprc config contains undo-levels set to 100.
    
    Args:
        traj: Trajectory data with episode information
        env_info: Environment information including episode directory and copy utilities
        task_info: Task information
        
    Returns:
        dict: {"passed": bool, "score": int, "feedback": str}
    """
    
    # Get episode directory and copy utilities
    episode_dir = env_info.get("episode_dir")
    copy_from_env = env_info.get("copy_from_env")
    
    if not episode_dir:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No episode directory found"
        }
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy utilities available"
        }
    
    # Create temporary directory for copied files
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        # Define container path for gimprc config file
        container_gimprc = "/home/ga/.config/GIMP/2.10/gimprc"
        
        # Define host path
        host_gimprc = temp_path / "gimprc"
        
        # Try to copy gimprc from container
        success, error = copy_file_from_container(copy_from_env, container_gimprc, host_gimprc)
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access GIMP configuration file: {error}"
            }
        
        try:
            # Read and parse the gimprc file
            with open(host_gimprc, 'r') as f:
                content = f.readlines()
            
            # Look for undo-levels setting
            undo_levels_found = False
            undo_levels_value = None
            
            for line_num, line in enumerate(content, 1):
                # Skip comments and empty lines
                if line.startswith('#') or line.strip() == '':
                    continue
                
                # Parse GIMP config line format: (setting-name value)
                stripped = line.strip().lstrip('(').rstrip(')\n')
                if not stripped:
                    continue
                
                items = stripped.split()
                if len(items) >= 2 and items[0] == 'undo-levels':
                    undo_levels_found = True
                    undo_levels_value = items[-1]  # Last item is the value
                    logging.debug(f"Found undo-levels on line {line_num}: {undo_levels_value}")
                    break
            
            feedback_parts = []
            feedback_parts.append(f"Configuration file found: ✅")
            
            if undo_levels_found:
                feedback_parts.append(f"undo-levels setting found: ✅")
                feedback_parts.append(f"Current value: {undo_levels_value}")
                
                # Check if the value is 100
                if undo_levels_value == "100":
                    feedback_parts.append("undo-levels set to 100: ✅")
                    feedback_parts.append("🎉 GIMP undo configuration updated successfully!")
                    return {
                        "passed": True,
                        "score": 100,
                        "feedback": " | ".join(feedback_parts)
                    }
                else:
                    feedback_parts.append(f"undo-levels set to 100: ❌ (found {undo_levels_value})")
                    return {
                        "passed": False,
                        "score": 0,
                        "feedback": " | ".join(feedback_parts)
                    }
            else:
                feedback_parts.append("undo-levels setting found: ❌")
                feedback_parts.append("❌ undo-levels setting not found in configuration")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": " | ".join(feedback_parts)
                }
            
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Error reading configuration file: {str(e)}"
            }
