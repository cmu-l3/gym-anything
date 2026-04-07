#!/usr/bin/env python3
"""Verifier for Configure Course Metadata Tags task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_course_metadata_tags(traj, env_info, task_info):
    """
    Verify that custom course fields and tags were configured correctly.

    Scoring (100 points):
    - Category "Catalog Info" exists (10 points)
    - Field "Faculty" exists with correct type (20 points)
    - Field is in the correct category (10 points)
    - Tag "STEM" exists and is applied to BIO101 (25 points)
    - Field "Faculty" is set to "Science" for BIO101 (35 points)

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_course_metadata_tags_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Category check (10 pts)
        if result.get('category_exists', False):
            score += 10
            feedback_parts.append("Category 'Catalog Info' created")
        else:
            feedback_parts.append("Category 'Catalog Info' NOT found")

        # 2. Field Existence (20 pts)
        if result.get('field_exists', False):
            score += 20
            feedback_parts.append("Field 'Faculty' created")
            # Check type (Short text is 'text')
            ftype = result.get('field_type', '')
            if ftype != 'text':
                feedback_parts.append(f"(Warning: Field type is '{ftype}', expected 'text')")
        else:
            feedback_parts.append("Field 'Faculty' NOT found")

        # 3. Field Structure (10 pts)
        if result.get('field_category_match', False):
            score += 10
            feedback_parts.append("Field is in correct category")
        elif result.get('field_exists', False):
            feedback_parts.append("Field is in WRONG category")

        # 4. Tag Application (25 pts)
        if result.get('tag_linked', False):
            score += 25
            subscores['tag_applied'] = True
            feedback_parts.append("Tag 'STEM' applied to BIO101")
        elif result.get('tag_exists', False):
            score += 10 # Partial credit for creating tag but not applying
            subscores['tag_applied'] = False
            feedback_parts.append("Tag 'STEM' exists but NOT applied to BIO101")
        else:
            subscores['tag_applied'] = False
            feedback_parts.append("Tag 'STEM' NOT found")

        # 5. Field Data Application (35 pts)
        field_val = result.get('field_value', '')
        if result.get('field_value_correct', False):
            score += 35
            subscores['data_correct'] = True
            feedback_parts.append("Metadata 'Faculty' set to 'Science'")
        elif field_val:
            # Partial credit if value is present but wrong
            score += 10
            subscores['data_correct'] = False
            feedback_parts.append(f"Metadata set to '{field_val}' (expected 'Science')")
        else:
            subscores['data_correct'] = False
            feedback_parts.append("Metadata 'Faculty' not set for BIO101")

        # Anti-gaming check
        initial_count = int(result.get('initial_field_count', 0))
        current_count = int(result.get('current_field_count', 0))
        if result.get('field_exists', False) and current_count <= initial_count:
            feedback_parts.append("(Note: Field count did not increase - reused existing field?)")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export may have failed"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}