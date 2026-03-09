#!/usr/bin/env python3
"""Verifier for setup_version_control task."""

import json
import re
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_setup_version_control(traj, env_info, task_info):
    """
    Verify the complete Git workflow was set up correctly.

    Scoring (100 points):
    - .git directory exists (VCS initialized): 15 pts
    - .gitignore exists with target/ exclusion: 15 pts
    - .gitignore excludes .idea/ and *.iml: 10 pts
    - At least 1 commit exists on initial branch: 15 pts
    - feature/add-merge-sort branch exists: 15 pts
    - MergeSort.java exists and compiles: 15 pts
    - MergeSortTest.java has >=3 @Test methods: 15 pts
    - VLM bonus: up to +10 pts

    Pass threshold: >= 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/sort-algorithms')
    feature_branch = metadata.get('feature_branch', 'feature/add-merge-sort')
    min_test_methods = metadata.get('min_test_methods', 3)

    # Get result JSON
    result = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        logger.debug(f"Could not read task_result.json: {e}")

    score = 0
    feedback_parts = []

    git_initialized = result.get('git_initialized', False)
    gitignore_exists = result.get('gitignore_exists', False)
    gitignore_has_target = result.get('gitignore_has_target', False)
    gitignore_has_idea = result.get('gitignore_has_idea', False)
    gitignore_has_iml = result.get('gitignore_has_iml', False)
    commit_count = result.get('commit_count', 0)
    feature_branch_exists = result.get('feature_branch_exists', False)
    mergesort_exists = result.get('mergesort_exists', False)
    mergesort_compiles = result.get('mergesort_compiles', False)
    mergesort_test_exists = result.get('mergesort_test_exists', False)
    mergesort_test_count = result.get('mergesort_test_count', 0)

    # --- Criterion 1: Git initialized (15 pts) ---
    if git_initialized:
        score += 15
        feedback_parts.append("Git repository initialized")
    else:
        feedback_parts.append("Git repository NOT initialized (no .git directory)")
        # Nothing else can be verified without git
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # --- Criterion 2: .gitignore with target/ (15 pts) ---
    if gitignore_exists and gitignore_has_target:
        score += 15
        feedback_parts.append(".gitignore exists with target/ exclusion")
    elif gitignore_exists:
        score += 5
        feedback_parts.append(".gitignore exists but target/ not excluded")
    else:
        feedback_parts.append(".gitignore not found")

    # --- Criterion 3: .gitignore excludes .idea/ and *.iml (10 pts) ---
    if gitignore_has_idea and gitignore_has_iml:
        score += 10
        feedback_parts.append(".gitignore excludes .idea/ and *.iml")
    elif gitignore_has_idea or gitignore_has_iml:
        score += 5
        feedback_parts.append(".gitignore partially covers IDE files")
    else:
        feedback_parts.append(".gitignore does not exclude IntelliJ IDE files")

    # --- Criterion 4: Initial commit exists (15 pts) ---
    if commit_count >= 1:
        score += 15
        initial_msg = result.get('initial_commit_message', '')
        feedback_parts.append(f"At least 1 commit exists (first: '{initial_msg[:50]}')")
    else:
        feedback_parts.append("No commits found")

    # --- Criterion 5: Feature branch exists (15 pts) ---
    if feature_branch_exists:
        score += 15
        feedback_parts.append(f"Branch '{feature_branch}' exists")
    else:
        feedback_parts.append(f"Branch '{feature_branch}' not found")

    # --- Criterion 6: MergeSort.java exists and compiles (15 pts) ---
    if mergesort_exists and mergesort_compiles:
        score += 15
        feedback_parts.append("MergeSort.java exists and compiles successfully")
    elif mergesort_exists:
        score += 8
        feedback_parts.append("MergeSort.java exists but does not compile")
    else:
        feedback_parts.append("MergeSort.java not found")

    # --- Criterion 7: MergeSortTest has >= 3 test methods (15 pts) ---
    if mergesort_test_exists and mergesort_test_count >= min_test_methods:
        score += 15
        feedback_parts.append(f"MergeSortTest.java has {mergesort_test_count} @Test methods")
    elif mergesort_test_exists and mergesort_test_count > 0:
        partial = int(15 * mergesort_test_count / min_test_methods)
        score += partial
        feedback_parts.append(
            f"MergeSortTest.java has {mergesort_test_count} @Test methods "
            f"(need {min_test_methods})"
        )
    elif mergesort_test_exists:
        score += 3
        feedback_parts.append("MergeSortTest.java exists but no @Test methods found")
    else:
        feedback_parts.append("MergeSortTest.java not found")

    # --- VLM Verification ---
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from intellij_verification_utils import vlm_verify_intellij_task
        vlm_result = vlm_verify_intellij_task(
            traj, env_info,
            task_description=(
                "Set up Git version control for a Java project in IntelliJ IDEA: "
                "initialize Git repository, create .gitignore (target/, .idea/, *.iml), "
                "commit all source files, create branch 'feature/add-merge-sort', "
                "add MergeSort.java and MergeSortTest.java, commit on the branch."
            ),
            checklist_items=[
                "IntelliJ IDEA is open with the sort-algorithms project",
                "The VCS menu or Git tool window was used",
                "A commit dialog or Git commit was visible",
                "The Git branches panel or branch dropdown is visible",
                "A file named MergeSort.java is open or visible in the project tree",
                "The feature/add-merge-sort branch is shown as active or created",
            ]
        )
        if vlm_result and vlm_result.get('vlm_passed'):
            score = min(score + 10, 100)
        if vlm_result:
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
    except Exception as e:
        logger.debug(f"VLM verification skipped: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "git_initialized": git_initialized,
            "commit_count": commit_count,
            "feature_branch_exists": feature_branch_exists,
            "mergesort_exists": mergesort_exists,
            "mergesort_test_count": mergesort_test_count,
        }
    }
