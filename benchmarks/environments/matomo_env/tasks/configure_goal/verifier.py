#!/usr/bin/env python3
"""
Verifier for Configure Goal task in Matomo

Verification Strategy:
1. PRIMARY: Database verification via exported JSON
2. Check that goal was created with correct name, pattern, and revenue

Scoring (100 points):
- Goal exists with correct name: 35 points
- Pattern correct: 25 points
- Revenue correct: 15 points
- Match type correct: 10 points
- Created during task execution (anti-gaming): 15 points

Pass threshold: 70 points with goal record existing
"""

import sys
import os
import json
import logging
import tempfile
import re
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_string(s: str) -> str:
    """Normalize string for flexible comparison."""
    if not s:
        return ""
    return s.strip().lower()


def normalize_pattern(pattern: str) -> str:
    """Normalize URL pattern for comparison."""
    if not pattern:
        return ""
    pattern = pattern.strip().lower()
    # Remove leading slash if present for comparison
    return pattern.lstrip('/')


def verify_configure_goal(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that a conversion goal was configured in Matomo with correct information.

    Uses copy_from_env to retrieve exported results from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected = {
        "goal_name": metadata.get('expected_goal_name', 'Newsletter Signup'),
        "match_attribute": metadata.get('expected_match_attribute', 'url'),
        "pattern_type": metadata.get('expected_pattern_type', 'contains'),
        "pattern": metadata.get('expected_pattern', '/newsletter/thank-you'),
        "revenue": float(metadata.get('expected_revenue', 5.0))
    }

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_goal_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "goal_exists": False,
            "pattern_correct": False,
            "revenue_correct": False,
            "match_type_correct": False,
            "created_during_task": False
        }

        # Extract data from result
        goal_found = result.get('goal_found', False)
        created_during_task = result.get('created_during_task', False)
        goal = result.get('goal', {})
        initial_count = result.get('initial_goal_count', 0)
        current_count = result.get('current_goal_count', 0)
        initial_goal_ids = result.get('initial_goal_ids', '')

        logger.info(f"Result: found={goal_found}, created_during_task={created_during_task}")
        logger.info(f"Goal data: {goal}")
        logger.info(f"Initial goal IDs: {initial_goal_ids}")

        # CRITERION 1: Goal exists with correct name (35 points)
        if goal_found:
            actual_name = goal.get('name', '')

            if normalize_string(actual_name) == normalize_string(expected["goal_name"]):
                score += 35
                subscores["goal_exists"] = True
                feedback_parts.append(f"Goal '{expected['goal_name']}' found in database")
            else:
                feedback_parts.append(f"Name mismatch: expected '{expected['goal_name']}', got '{actual_name}'")
        else:
            feedback_parts.append(f"Goal '{expected['goal_name']}' NOT found in database")

            # Check if any new goals were added
            if current_count > initial_count:
                feedback_parts.append(f"Note: {current_count - initial_count} new goal(s) added but not with expected name")
            else:
                feedback_parts.append("No new goals were added to the database")

            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: Pattern correct (25 points)
        actual_pattern = goal.get('pattern', '')
        expected_pattern_normalized = normalize_pattern(expected["pattern"])
        actual_pattern_normalized = normalize_pattern(actual_pattern)

        # STRICT matching: patterns must be exactly equal after normalization
        # This prevents gaming where agent adds extra text to expected pattern
        # e.g., "/newsletter/thank-you-extra" should NOT match "/newsletter/thank-you"
        pattern_match = (expected_pattern_normalized == actual_pattern_normalized)

        if pattern_match:
            score += 25
            subscores["pattern_correct"] = True
            feedback_parts.append(f"Pattern correct: {expected['pattern']}")
        else:
            feedback_parts.append(f"Pattern incorrect: expected exact '{expected['pattern']}', got '{actual_pattern}'")

        # CRITERION 3: Revenue correct (15 points)
        actual_revenue = goal.get('revenue', '0')
        try:
            actual_revenue_float = float(actual_revenue)
            # Allow some tolerance for floating point
            if abs(actual_revenue_float - expected["revenue"]) < 0.01:
                score += 15
                subscores["revenue_correct"] = True
                feedback_parts.append(f"Revenue correct: {expected['revenue']}")
            else:
                feedback_parts.append(f"Revenue incorrect: expected {expected['revenue']}, got {actual_revenue_float}")
        except (ValueError, TypeError):
            feedback_parts.append(f"Revenue invalid: got '{actual_revenue}'")

        # CRITERION 4: Match type correct (10 points)
        actual_pattern_type = goal.get('pattern_type', '')
        actual_match_attribute = goal.get('match_attribute', '')

        # Check pattern type (contains, exact, etc.)
        if normalize_string(actual_pattern_type) == normalize_string(expected["pattern_type"]):
            score += 5
            subscores["match_type_correct"] = True
            feedback_parts.append(f"Pattern type correct: {expected['pattern_type']}")

        # Check match attribute (url, title, etc.)
        if normalize_string(actual_match_attribute) == normalize_string(expected["match_attribute"]):
            score += 5
            if not subscores["match_type_correct"]:
                subscores["match_type_correct"] = True
            feedback_parts.append(f"Match attribute correct: {expected['match_attribute']}")
        else:
            feedback_parts.append(f"Match attribute: expected '{expected['match_attribute']}', got '{actual_match_attribute}'")

        # CRITERION 5: Created during task (anti-gaming) (15 points)
        if created_during_task:
            score += 15
            subscores["created_during_task"] = True
            feedback_parts.append(f"Goal created during task execution")
        else:
            feedback_parts.append(f"Goal may have existed before task (count didn't increase)")

        # Determine pass/fail
        # Must have: goal exists (35) + created during task (15) = 50 minimum
        # Plus at least 20 more points from other criteria for 70 total
        key_criteria_met = subscores["goal_exists"] and subscores["created_during_task"]
        passed = score >= 70 and key_criteria_met

        # If goal exists but not created during task, cap score and fail
        if subscores["goal_exists"] and not subscores["created_during_task"]:
            feedback_parts.append("Anti-gaming check failed: goal record may not have been created during this task")
            passed = False

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "expected": expected,
                "actual": goal,
                "initial_count": initial_count,
                "current_count": current_count
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found in container")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result file not found - task may not have completed properly",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }
