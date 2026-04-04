#!/usr/bin/env python3
"""
Verifier for Windows Notepad hello_world task.
Checks if the user successfully created a hello.txt file with 'Hello, World!' content.
"""

import logging
from pathlib import Path

logging.basicConfig(level=logging.DEBUG)


def check_hello_world(traj, env_info, task_info):
    """
    Verify that hello.txt was created with correct content.

    Success criteria:
    1. File hello.txt exists on Desktop (or shared folder after export)
    2. File contains 'Hello, World!' (case-insensitive match for flexibility)
    """

    # Get copy function from env_info
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in env_info"
        }

    # Try to copy the result file from Windows
    import tempfile
    import os

    temp_dir = tempfile.mkdtemp(prefix="verify_hello_")

    # Possible result locations (after export_result.ps1 runs)
    # Note: Use forward slashes or raw strings for Windows paths
    possible_paths = [
        "C:/workspace/results/result_hello.txt",
        "C:/Users/Docker/Desktop/hello.txt",
        "/workspace/results/result_hello.txt",  # Linux-style path for SCP
    ]

    result_content = None
    found_path = None

    for remote_path in possible_paths:
        try:
            local_path = os.path.join(temp_dir, "hello.txt")
            copy_from_env(remote_path, local_path)

            if os.path.exists(local_path):
                with open(local_path, 'r', encoding='utf-8', errors='ignore') as f:
                    result_content = f.read()
                found_path = remote_path
                break
        except Exception as e:
            logging.debug(f"Could not copy from {remote_path}: {e}")
            continue

    # Clean up temp dir
    try:
        import shutil
        shutil.rmtree(temp_dir)
    except:
        pass

    # Check results
    if result_content is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not find hello.txt file. Make sure to save the file on the Desktop."
        }

    # Normalize content for comparison
    content_lower = result_content.lower().strip()

    # Check for required text
    has_hello = "hello" in content_lower
    has_world = "world" in content_lower
    has_hello_world = "hello, world" in content_lower or "hello world" in content_lower

    # Calculate score
    score = 0
    feedback_parts = []

    if has_hello_world:
        score = 100
        feedback_parts.append("'Hello, World!' found in file")
    elif has_hello and has_world:
        score = 80
        feedback_parts.append("Found 'hello' and 'world' but not exact phrase")
    elif has_hello or has_world:
        score = 40
        feedback_parts.append("Partial match - file exists but content incomplete")
    else:
        score = 20
        feedback_parts.append("File exists but does not contain expected text")

    feedback_parts.append(f"File location: {found_path}")
    feedback_parts.append(f"Content preview: {result_content[:100]}...")

    passed = score >= 80

    if passed:
        feedback_parts.insert(0, "Task completed successfully!")
    else:
        feedback_parts.insert(0, "Task not fully completed")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
