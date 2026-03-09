#!/usr/bin/env python3
"""Verifier for ci_pipeline_for_flask_api task.

Scoring (100 points):
- At least 1 pipeline definition exists in the project: 25 pts
- Pipeline has a CI trigger that includes 'main': 20 pts
- Pipeline YAML contains Python dependency installation: 30 pts
- Pipeline YAML contains test execution (pytest or equivalent): 25 pts

Pass threshold: 70 points
"""

import json
import logging
import os
import re
import tempfile

logger = logging.getLogger(__name__)


def verify_ci_pipeline_for_flask_api(traj, env_info, task_info):
    """Verify CI pipeline creation for the Flask inventory API."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        try:
            copy_from_env(
                "C:/Users/Docker/task_results/ci_pipeline_result.json",
                tmp.name,
            )
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Result file not found: {e}"}

        try:
            with open(tmp.name, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    subscores = {}

    pipeline_count = result.get("pipeline_count", 0)
    yaml_content = result.get("combined_yaml_snippet", "").lower()
    has_yaml = result.get("yaml_content_found", False) and len(yaml_content) > 10

    # -----------------------------------------------------------------------
    # Criterion 1: Pipeline exists (25 pts)
    # -----------------------------------------------------------------------
    if pipeline_count >= 1:
        score += 25
        subscores["pipeline_exists"] = True
        feedback_parts.append(f"{pipeline_count} pipeline definition(s) created")
    else:
        subscores["pipeline_exists"] = False
        feedback_parts.append("No pipeline definitions found")
        # If no pipeline at all, nothing else can be verified
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
        }

    # -----------------------------------------------------------------------
    # Criterion 2: CI trigger that includes main (20 pts)
    # -----------------------------------------------------------------------
    has_ci_trigger = result.get("has_ci_trigger", False)
    has_main_trigger = result.get("has_main_trigger", False)

    # Also check YAML directly
    if has_yaml:
        if re.search(r"trigger\s*:", yaml_content) or re.search(r"^trigger:", yaml_content, re.MULTILINE):
            has_ci_trigger = True
        if "main" in yaml_content:
            has_main_trigger = True

    if has_main_trigger and has_ci_trigger:
        score += 20
        subscores["ci_trigger"] = True
        feedback_parts.append("CI trigger configured targeting main branch")
    elif has_ci_trigger:
        score += 10
        subscores["ci_trigger"] = "partial"
        feedback_parts.append("CI trigger found but main branch not clearly targeted")
    else:
        subscores["ci_trigger"] = False
        feedback_parts.append("No CI trigger detected in pipeline")

    # -----------------------------------------------------------------------
    # Criterion 3: Python dependency installation (30 pts)
    # -----------------------------------------------------------------------
    has_deps = result.get("has_dependency_install", False)
    has_python = result.get("has_python_setup", False)

    # Also check YAML content directly
    if has_yaml:
        if re.search(r"pip\s+install|pip3\s+install", yaml_content):
            has_deps = True
        if re.search(r"requirements\.txt", yaml_content):
            has_deps = True
        if re.search(r"python|usepythonversion", yaml_content):
            has_python = True

    if has_deps:
        score += 30
        subscores["dependencies_installed"] = True
        if has_python:
            feedback_parts.append("Python setup and dependency installation found in pipeline")
        else:
            feedback_parts.append("Dependency installation found in pipeline (pip install / requirements.txt)")
    elif has_python:
        score += 15
        subscores["dependencies_installed"] = "partial"
        feedback_parts.append("Python setup found but no dependency installation detected")
    else:
        subscores["dependencies_installed"] = False
        feedback_parts.append("No Python setup or dependency installation in pipeline YAML")

    # -----------------------------------------------------------------------
    # Criterion 4: Test execution (pytest or equivalent) (25 pts)
    # -----------------------------------------------------------------------
    has_tests = result.get("has_test_execution", False)

    if has_yaml:
        if re.search(r"pytest|python\s+-m\s+pytest|python\s+-m\s+unittest", yaml_content):
            has_tests = True
        # Also accept generic 'test' scripts if they appear meaningful
        elif re.search(r"run.*test|test.*run|script.*test", yaml_content):
            has_tests = True

    if has_tests:
        score += 25
        subscores["test_execution"] = True
        feedback_parts.append("Test execution step (pytest/unittest) found in pipeline")
    else:
        subscores["test_execution"] = False
        feedback_parts.append("No test execution detected in pipeline YAML")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "subscores": subscores,
        "details": {
            "pipeline_count": pipeline_count,
            "yaml_found": has_yaml,
            "yaml_length": len(result.get("combined_yaml_snippet", "")),
            "has_ci_trigger": has_ci_trigger,
            "has_main_trigger": has_main_trigger,
            "has_python": has_python,
            "has_deps": has_deps,
            "has_tests": has_tests,
        },
    }
