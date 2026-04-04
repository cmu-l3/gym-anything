#!/usr/bin/env python3
"""
Verifier for VSCode Unsaved Work Recovery task
"""

import sys
import os
import logging
import tempfile
import json

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_recovery(traj, env_info, task_info):
    """
    Verify that all three backup files were successfully recovered.
    
    Checks:
    1. authentication.py exists at src/authentication.py
    2. authentication.py contains required bcrypt code
    3. user_settings.json exists at config/user_settings.json
    4. user_settings.json contains required timeout setting
    5. URGENT_NOTES.md exists at docs/URGENT_NOTES.md
    6. URGENT_NOTES.md contains required root cause text
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    workspace = "/home/ga/workspace/bugfix-project"
    
    expected_files = {
        "authentication.py": {
            "container_path": f"{workspace}/src/authentication.py",
            "required_content": ["import bcrypt", "bcrypt.hashpw"],
            "min_size": 100,
            "description": "Security fix with bcrypt implementation"
        },
        "user_settings.json": {
            "container_path": f"{workspace}/config/user_settings.json",
            "required_content": ['"api_timeout": 30'],
            "min_size": 50,
            "description": "Configuration with updated API timeout",
            "is_json": True
        },
        "URGENT_NOTES.md": {
            "container_path": f"{workspace}/docs/URGENT_NOTES.md",
            "required_content": ["root cause: missing salt validation", "bcrypt"],
            "min_size": 80,
            "description": "Investigation notes with root cause analysis"
        }
    }
    
    feedback_parts = []
    files_recovered = 0
    total_files = len(expected_files)
    
    for filename, specs in expected_files.items():
        file_path = specs["container_path"]
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(filename)[1])
        
        try:
            # Copy file from container
            copy_from_env(file_path, temp_file.name)
            
            # Check if file exists and has content
            if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
                feedback_parts.append(f"❌ {filename} not found at {file_path}")
                continue
            
            # Read file content
            content = read_file_content(temp_file.name)
            
            if not content:
                feedback_parts.append(f"❌ {filename} is empty or unreadable")
                continue
            
            # Check minimum size
            if len(content) < specs["min_size"]:
                feedback_parts.append(f"❌ {filename} is too small ({len(content)} bytes, expected >{specs['min_size']})")
                continue
            
            # For JSON files, validate JSON structure
            if specs.get("is_json", False):
                try:
                    json_data = json.loads(content)
                    if not isinstance(json_data, dict):
                        feedback_parts.append(f"❌ {filename} is not a valid JSON object")
                        continue
                except json.JSONDecodeError as e:
                    feedback_parts.append(f"❌ {filename} is not valid JSON: {str(e)}")
                    continue
            
            # Check required content
            missing_content = []
            for required in specs["required_content"]:
                if required not in content:
                    missing_content.append(required)
            
            if missing_content:
                feedback_parts.append(f"❌ {filename} missing required content: {missing_content[:2]}")  # Show first 2 missing items
                continue
            
            # File successfully recovered!
            feedback_parts.append(f"✅ {filename} successfully recovered with correct content")
            files_recovered += 1
            
        except Exception as e:
            logger.error(f"Error verifying {filename}: {e}")
            feedback_parts.append(f"❌ {filename} verification error: {str(e)[:50]}")
        finally:
            # Clean up temp file
            if os.path.exists(temp_file.name):
                try:
                    os.unlink(temp_file.name)
                except:
                    pass
    
    # Calculate score and success
    score = int((files_recovered / total_files) * 100)
    passed = (files_recovered == total_files)  # All files must be recovered
    
    # Build feedback message
    if passed:
        feedback = f"🎉 All {total_files} files successfully recovered from VSCode backups! | " + " | ".join(feedback_parts)
    else:
        feedback = f"⚠️ Recovered {files_recovered}/{total_files} files. | " + " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
