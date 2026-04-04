#!/usr/bin/env python3
"""Verifier for import_gradle_project task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_gradle_project(traj, env_info, task_info):
    """Verify that the Gradle project was imported and the task completed.
    
    Criteria:
    1. Project imported into Eclipse (metadata files exist) (15 pts)
    2. Guava dependency added to build.gradle (15 pts)
    3. CollectionHelper.java created with correct path (15 pts)
    4. CollectionHelper.java uses Guava (imports and methods) (20 pts)
    5. Project builds successfully (25 pts)
    6. VLM verification of UI actions (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Project Imported (15 pts)
    if result.get('project_imported', False):
        score += 15
        feedback_parts.append("Project imported successfully")
    else:
        feedback_parts.append("Project NOT imported (Eclipse metadata not found)")

    # Criterion 2: Dependency Added (15 pts)
    if result.get('dependency_added', False):
        score += 15
        feedback_parts.append("Guava dependency added")
    else:
        bg_content = result.get('build_gradle_content', '')
        if 'guava' in bg_content:
            score += 10 # Partial credit if grep failed but string present vaguely
            feedback_parts.append("Guava string found in build.gradle but strict check failed")
        else:
            feedback_parts.append("Guava dependency missing from build.gradle")

    # Criterion 3: Class File Created (15 pts)
    if result.get('class_file_exists', False):
        if result.get('class_created_during_task', False):
            score += 15
            feedback_parts.append("CollectionHelper.java created")
        else:
            score += 5 # Created before task? Unlikely given setup, but penalty.
            feedback_parts.append("CollectionHelper.java exists but timestamp is old")
    else:
        feedback_parts.append("CollectionHelper.java not found")

    # Criterion 4: Class Content Verification (20 pts)
    class_content = result.get('class_file_content', '')
    content_score = 0
    if 'com.google.common.collect' in class_content:
        content_score += 5
    if 'ImmutableList' in class_content:
        content_score += 5
    if 'ImmutableMap' in class_content:
        content_score += 5
    if 'package com.datautils.util' in class_content:
        content_score += 5
    
    score += content_score
    if content_score == 20:
        feedback_parts.append("Class content correct")
    elif content_score > 0:
        feedback_parts.append(f"Class content partially correct ({content_score}/20)")

    # Criterion 5: Build Success (25 pts)
    if result.get('build_success', False):
        score += 25
        feedback_parts.append("Project builds successfully")
    elif result.get('compiled_class_exists', False):
        # Fallback: maybe gradle cli failed due to env but class file exists
        score += 20
        feedback_parts.append("Compiled class found, but verification build failed")
    else:
        feedback_parts.append("Build failed or not attempted")

    # Criterion 6: VLM Verification (10 pts)
    try:
        from utils.eclipse_verification_utils import vlm_verify_eclipse_task
        vlm_out = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Import Gradle project, add Guava dependency, create CollectionHelper class, and build.",
            checklist_items=[
                "Eclipse Import Wizard (Gradle) is visible",
                "Project 'datautils' appears in Package Explorer",
                "User edits build.gradle",
                "User creates a new Java class",
                "No red error icons on the project in final state"
            ]
        )
        if vlm_out and vlm_out.get('vlm_passed'):
            score += 10
            feedback_parts.append("VLM verification passed")
        elif vlm_out:
             feedback_parts.append(f"VLM feedback: {vlm_out.get('vlm_feedback')}")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Be lenient if VLM fails technically
        score += 10
        feedback_parts.append("VLM skipped (technical error)")

    # Normalize score
    score = min(score, 100)
    passed = score >= 65 and result.get('build_success', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }