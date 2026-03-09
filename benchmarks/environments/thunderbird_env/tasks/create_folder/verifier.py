#!/usr/bin/env python3
"""
Verifier for create folder task

Checks that a folder named 'Work' was created in Local Folders
"""
import sys
import os
from pathlib import Path

# Add utils to path
# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from thunderbird_verification_utils import *


def verify_folder_created(traj, env_info, task_info):
    """
    Verify that a folder named 'Work' was created
    """
    copy_from_env = env_info.get('copy_from_env')

    # Get profile directory
    profile_dir = get_thunderbird_profile_dir(username="ga")
    if not profile_dir:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Thunderbird profile not found"
        }

    # We need to copy the Mail folder to check for the new folder
    # Since we're checking folder existence, we can query directly via env
    # Or copy the folder structure

    # For now, let's copy a marker file or check via the runner
    # Actually, let's just copy the entire Mail/Local Folders directory listing

    success, files, error = setup_thunderbird_verification(
        copy_from_env,
        ["Mail/Local Folders/Work", "Mail/Local Folders/Inbox"],
        username="ga"
    )

    # Check if Work folder exists by attempting to copy it
    work_folder = files.get("Work")

    if work_folder and work_folder.exists():
        cleanup_verification_temp()
        return {
            "passed": True,
            "score": 100,
            "feedback": "Folder 'Work' created successfully in Local Folders"
        }

    # Alternative check: use the verify_folder_exists function
    # But we need the actual profile dir from inside container
    # Let's try a different approach

    cleanup_verification_temp()

    # Try to copy the prefs.js which might contain folder info
    success2, files2, error2 = setup_thunderbird_verification(
        copy_from_env,
        ["prefs.js"],
        username="ga"
    )

    if success2:
        prefs_file = files2.get("prefs.js")
        if prefs_file and prefs_file.exists():
            # Check if Work folder is mentioned in prefs
            with open(prefs_file, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                if 'Work' in content:
                    cleanup_verification_temp()
                    return {
                        "passed": True,
                        "score": 100,
                        "feedback": "Folder 'Work' created successfully"
                    }

    cleanup_verification_temp()
    return {
        "passed": False,
        "score": 0,
        "feedback": "Folder 'Work' not found in Local Folders. Make sure to create a folder named exactly 'Work'"
    }
