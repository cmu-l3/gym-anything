#!/usr/bin/env python3
"""Verifier for fix_build_errors task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fix_build_errors(traj, env_info, task_info):
    """Verify that all 3 build errors were fixed.

    Criteria:
    1. pom.xml: joda-time version is valid (not 999.0.0) (20 pts)
    2. HelloWorld.java: LocaleTime changed to LocalTime (20 pts)
    3. Greeter.java: returns a String value (20 pts)
    4. Project builds successfully (class files generated) (30 pts)
    5. Files were actually modified (not still broken) (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/gs-maven-broken')

    score = 0
    feedback_parts = []

    def copy_and_read(remote_path):
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

    # --- Criterion 1: pom.xml fixed (20 pts) ---
    pom_content = copy_and_read(f"{project_dir}/pom.xml")
    if pom_content:
        # Check that 999.0.0 is gone
        if '999.0.0' not in pom_content:
            # Check that a valid joda-time version is present
            version_match = re.search(r'<version>\s*(\d+\.\d+(?:\.\d+)?)\s*</version>', pom_content)
            if version_match and 'joda-time' in pom_content:
                score += 20
                feedback_parts.append(f"pom.xml fixed: joda-time version {version_match.group(1)}")
            else:
                score += 10
                feedback_parts.append("pom.xml: 999.0.0 removed but joda-time version unclear")
        else:
            feedback_parts.append("pom.xml: still contains version 999.0.0")
    else:
        feedback_parts.append("pom.xml not found")

    # --- Criterion 2: HelloWorld.java fixed (20 pts) ---
    hw_content = copy_and_read(f"{project_dir}/src/main/java/hello/HelloWorld.java")
    if hw_content:
        has_locale_time = 'LocaleTime' in hw_content
        has_local_time = 'LocalTime' in hw_content

        if has_local_time and not has_locale_time:
            score += 20
            feedback_parts.append("HelloWorld.java fixed: LocalTime used correctly")
        elif has_locale_time:
            feedback_parts.append("HelloWorld.java: still contains LocaleTime typo")
        else:
            feedback_parts.append("HelloWorld.java: LocalTime not found")
    else:
        feedback_parts.append("HelloWorld.java not found")

    # --- Criterion 3: Greeter.java fixed (20 pts) ---
    gr_content = copy_and_read(f"{project_dir}/src/main/java/hello/Greeter.java")
    if gr_content:
        # Check that return statement has a string value
        has_string_return = bool(re.search(r'return\s+["\'].*["\']', gr_content))
        has_bare_return = bool(re.search(r'return\s*;', gr_content))

        if has_string_return:
            score += 20
            feedback_parts.append("Greeter.java fixed: returns a string value")
        elif has_bare_return:
            feedback_parts.append("Greeter.java: still has bare 'return;'")
        else:
            # Check if it returns something (variable, method call, etc.)
            has_some_return = bool(re.search(r'return\s+\S', gr_content))
            if has_some_return:
                score += 15
                feedback_parts.append("Greeter.java: returns a value (not a string literal)")
            else:
                feedback_parts.append("Greeter.java: no valid return statement found")
    else:
        feedback_parts.append("Greeter.java not found")

    # --- Criterion 4: Build success (30 pts) ---
    try:
        tmp_class = tempfile.NamedTemporaryFile(delete=False, suffix='.class')
        tmp_class.close()
        copy_from_env(f"{project_dir}/target/classes/hello/HelloWorld.class", tmp_class.name)
        with open(tmp_class.name, 'rb') as f:
            magic = f.read(4)
        os.unlink(tmp_class.name)
        if magic == b'\xca\xfe\xba\xbe':
            score += 30
            feedback_parts.append("Build successful (HelloWorld.class verified)")
        else:
            feedback_parts.append("HelloWorld.class found but invalid")
    except Exception:
        feedback_parts.append("Build not completed (no .class files)")

    # --- Criterion 5: Files were modified (10 pts) ---
    # If we got here with score > 0, files were clearly modified
    if score >= 60:
        score += 10
        feedback_parts.append("All source files modified from broken state")

    # --- VLM Verification ---
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from intellij_verification_utils import vlm_verify_intellij_task

        vlm_result = vlm_verify_intellij_task(
            traj, env_info,
            task_description="Fix 3 build errors in a Maven project (gs-maven-broken) using IntelliJ IDEA: "
                           "fix joda-time version in pom.xml, fix LocaleTime typo in HelloWorld.java, "
                           "fix missing return value in Greeter.java. Build project successfully.",
            checklist_items=[
                "IntelliJ IDEA is open with the gs-maven-broken project loaded",
                "Source files were edited (pom.xml, HelloWorld.java, or Greeter.java visible in editor)",
                "Code changes are visible in the editor tabs",
                "The project was built (Build menu or Maven executed)",
                "Build output shows success (no errors in Build panel or terminal)",
                "No red error markers visible in the editor gutter",
            ]
        )
        if vlm_result:
            if vlm_result.get('vlm_passed'):
                score = min(score + 10, 100)
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
    except Exception as e:
        logger.debug(f"VLM verification skipped: {e}")

    # Build success is a mandatory requirement - without it, task is not complete
    build_successful = 'Build successful' in ' '.join(feedback_parts)

    # Must have build success AND good score to pass
    passed = score >= 70 and build_successful

    if not build_successful and score >= 60:
        feedback_parts.append("NOTE: Task incomplete without successful build")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
