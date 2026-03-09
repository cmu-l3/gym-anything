#!/usr/bin/env python3
"""Verifier for Add Category task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_category(traj, env_info, task_info):
    """
    Verify that the expected category was created in Magento.

    Checks:
    1. Category was newly created (count increased during task)
    2. Category with expected name exists in database
    3. Category parent is Default Category (parent_id=2)
    4. Category is active (is_active=1)
    5. Category is included in navigation menu (include_in_menu=1)

    All criteria must be met for the task to pass.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Eco-Friendly')
    expected_parent_id = metadata.get('expected_parent_id', '2')
    expected_is_active = metadata.get('expected_is_active', True)
    expected_include_in_menu = metadata.get('expected_include_in_menu', True)

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/add_category_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []

        initial_count = result.get('initial_category_count', 0)
        current_count = result.get('current_category_count', 0)
        category_found = result.get('category_found', False)
        category = result.get('category', {})

        logger.info(f"Result: initial={initial_count}, current={current_count}, found={category_found}")
        logger.info(f"Category data: {category}")

        # Criterion 1: Category was newly created (count must increase)
        newly_created = current_count > initial_count
        if newly_created:
            criteria_passed += 1
            feedback_parts.append(f"Category created (count: {initial_count} -> {current_count})")
        else:
            feedback_parts.append(f"No new category created (count unchanged: {initial_count})")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "newly_created": False,
                    "category_exists": category_found,
                    "parent_correct": False,
                    "is_active": False,
                    "include_in_menu": False
                }
            }

        # Criterion 2: Category with expected name exists in database
        if category_found:
            criteria_passed += 1
            name = category.get('name', '')
            feedback_parts.append(f"Category '{name}' found in database")
        else:
            feedback_parts.append(f"Category with name '{expected_name}' NOT found in database")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "newly_created": newly_created,
                    "category_exists": False,
                    "parent_correct": False,
                    "is_active": False,
                    "include_in_menu": False
                }
            }

        # Criterion 3: Category parent is Default Category (parent_id=2)
        parent_id = category.get('parent_id', '')
        parent_correct = str(parent_id).strip() == str(expected_parent_id).strip()
        if parent_correct:
            criteria_passed += 1
            feedback_parts.append("Parent category correct (Default Category)")
        else:
            feedback_parts.append(f"Parent category incorrect: expected 'Default Category' (ID=2), got parent_id={parent_id}")

        # Criterion 4: Category is active
        is_active = category.get('is_active', '')
        is_active_correct = str(is_active).strip() == '1'
        if is_active_correct:
            criteria_passed += 1
            feedback_parts.append("Category is active")
        else:
            feedback_parts.append(f"Category is not active (is_active={is_active})")

        # Criterion 5: Category is included in navigation menu
        include_in_menu = category.get('include_in_menu', '')
        include_in_menu_correct = str(include_in_menu).strip() == '1'
        if include_in_menu_correct:
            criteria_passed += 1
            feedback_parts.append("Category included in navigation menu")
        else:
            feedback_parts.append(f"Category not in navigation menu (include_in_menu={include_in_menu})")

        # Calculate score - all criteria must be met
        score = int((criteria_passed / total_criteria) * 100)
        passed = criteria_passed == total_criteria

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "newly_created": newly_created,
                "category_exists": category_found,
                "parent_correct": parent_correct,
                "is_active": is_active_correct,
                "include_in_menu": include_in_menu_correct
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
