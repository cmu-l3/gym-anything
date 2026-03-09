#!/usr/bin/env python3
"""Verifier for refactor_rename_class task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_refactor_rename_class(traj, env_info, task_info):
    """Verify that the class was renamed using Eclipse refactoring.

    Criteria:
    1. Old file OldClassName.java is gone (20 pts)
    2. New file NewClassName.java exists with correct class name (30 pts)
    3. Main.java references updated to NewClassName (25 pts)
    4. Project compiles successfully (25 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/eclipse-workspace/refactor-demo')
    old_class_name = metadata.get('old_class_name', 'OldClassName')
    new_class_name = metadata.get('new_class_name', 'NewClassName')
    package = metadata.get('package', 'com.example.demo')

    package_path = package.replace('.', '/')
    old_file_path = f"{project_dir}/src/main/java/{package_path}/{old_class_name}.java"
    new_file_path = f"{project_dir}/src/main/java/{package_path}/{new_class_name}.java"
    main_file_path = f"{project_dir}/src/main/java/{package_path}/Main.java"

    score = 0
    feedback_parts = []

    def copy_and_read(remote_path):
        """Copy a file from the environment and read its contents."""
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(remote_path, tmp.name)
            with open(tmp.name, 'r') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception as e:
            logger.debug(f"Failed to read {remote_path}: {e}")
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
            return None

    def file_exists(remote_path):
        """Check if a file exists by trying to copy it."""
        content = copy_and_read(remote_path)
        return content is not None

    # --- Criterion 1: Old file gone (20 points) ---
    old_file_exists = file_exists(old_file_path)
    if not old_file_exists:
        score += 20
        feedback_parts.append(f"{old_class_name}.java removed")
    else:
        feedback_parts.append(f"{old_class_name}.java still exists")

    # --- Criterion 2: New file exists with correct class name (30 points) ---
    new_content = copy_and_read(new_file_path)
    if new_content:
        new_score = 15  # File exists
        # Check if class declaration has new name
        if re.search(rf'public\s+class\s+{new_class_name}\b', new_content):
            new_score += 15
            feedback_parts.append(f"{new_class_name}.java exists with correct class declaration")
        else:
            feedback_parts.append(f"{new_class_name}.java exists but class declaration not updated")
        score += new_score
    else:
        feedback_parts.append(f"{new_class_name}.java not found")

    # --- Criterion 3: Main.java references updated (25 points) ---
    main_content = copy_and_read(main_file_path)
    if main_content:
        has_new_ref = new_class_name in main_content
        has_old_ref = old_class_name in main_content

        if has_new_ref and not has_old_ref:
            score += 25
            feedback_parts.append("Main.java fully updated to use NewClassName")
        elif has_new_ref and has_old_ref:
            score += 10
            feedback_parts.append("Main.java partially updated (still has old references)")
        else:
            feedback_parts.append("Main.java not updated")
    else:
        feedback_parts.append("Main.java not found")

    # --- Criterion 4: Build success (25 points) ---
    try:
        tmp_class = tempfile.NamedTemporaryFile(delete=False, suffix='.class')
        tmp_class.close()
        copy_from_env(f"{project_dir}/target/classes/{package_path}/{new_class_name}.class", tmp_class.name)
        with open(tmp_class.name, 'rb') as f:
            magic = f.read(4)
        os.unlink(tmp_class.name)
        if magic == b'\xca\xfe\xba\xbe':
            score += 25
            feedback_parts.append("Build successful")
    except Exception:
        feedback_parts.append("Build not verified (no .class files)")

    # --- VLM Verification ---
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from eclipse_verification_utils import vlm_verify_eclipse_task

        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Rename OldClassName to NewClassName using Eclipse refactoring",
            checklist_items=[
                "Eclipse IDE is open and visible",
                "The project is open in Package Explorer",
                "Refactor > Rename dialog was used",
                "The new class name was entered",
                "Preview or OK was clicked to complete refactoring",
                "No errors shown after refactoring",
            ]
        )
        if vlm_result and vlm_result.get('vlm_passed'):
            score = min(score + 5, 100)
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
    except Exception as e:
        logger.debug(f"VLM verification skipped: {e}")

    # Pass criteria: old file gone, new file exists, Main updated
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
