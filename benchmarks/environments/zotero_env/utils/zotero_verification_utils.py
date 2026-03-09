#!/usr/bin/env python3
"""Shared verification utilities for Zotero environment."""

import json
import tempfile
import os


def load_result_json(copy_from_env):
    """Load result JSON from container using copy_from_env function.

    Args:
        copy_from_env: Function to copy files from container

    Returns:
        dict: Parsed JSON result or None if failed
    """
    if not copy_from_env:
        return None

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Failed to load result JSON: {e}")
        return None
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)


def create_feedback(parts):
    """Create feedback string from list of parts.

    Args:
        parts: List of feedback strings

    Returns:
        str: Joined feedback string
    """
    return " | ".join(parts)


def score_boolean_criterion(condition, max_points, true_msg, false_msg):
    """Score a boolean criterion.

    Args:
        condition: Boolean condition to check
        max_points: Maximum points for this criterion
        true_msg: Message if condition is true
        false_msg: Message if condition is false

    Returns:
        tuple: (score, message)
    """
    if condition:
        return max_points, true_msg
    else:
        return 0, false_msg


def score_range_criterion(value, min_val, max_val, max_points, partial_threshold=0.5):
    """Score a criterion with a value range.

    Args:
        value: Actual value
        min_val: Minimum acceptable value
        max_val: Maximum acceptable value
        max_points: Maximum points for this criterion
        partial_threshold: Threshold for partial credit (default 0.5)

    Returns:
        tuple: (score, message)
    """
    if min_val <= value <= max_val:
        return max_points, f"Value in range: {value} (expected {min_val}-{max_val})"
    elif value >= min_val * partial_threshold:
        partial = int(max_points * value / min_val)
        return partial, f"Partial: {value} (expected {min_val}-{max_val})"
    else:
        return 0, f"Value too low: {value} (expected {min_val}-{max_val})"
