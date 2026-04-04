#!/usr/bin/env python3
"""Verifier for transform_hl7_format task."""

import json
import tempfile
import os


def verify_transform_hl7_format(traj, env_info, task_info):
    """Verify that an HL7 transformation channel was created and configured."""

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_channel_name = metadata.get('channel_name', 'HL7 Transformer Channel')
    target_format = metadata.get('target_format', 'XML')

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/transform_hl7_format_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract results
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    transformer_exists = result.get('transformer_exists', False)
    channel_name = result.get('channel_name', '')
    has_transformer = result.get('has_transformer', False)
    output_format = result.get('output_format', '')
    transformed_output = result.get('transformed_output', False)

    # Scoring criteria - rebalanced
    score = 0
    feedback_parts = []

    # Check if a new channel was created (15 points)
    if current_count > initial_count:
        score += 15
        feedback_parts.append(f"New channel created (count: {initial_count} -> {current_count})")
    else:
        feedback_parts.append(f"No new channel detected (count: {initial_count})")

    # Check if transformer channel exists (15 points)
    if transformer_exists:
        score += 15
        feedback_parts.append(f"Transformer channel found: '{channel_name}'")

        # Check if channel name matches expected pattern (10 points)
        name_lower = channel_name.lower()
        if 'transform' in name_lower or 'transformer' in name_lower:
            if 'hl7' in name_lower:
                score += 10
                feedback_parts.append("Channel name matches expected pattern")
            else:
                score += 5
                feedback_parts.append("Channel name contains 'transform' but not 'hl7'")
        else:
            feedback_parts.append("Channel name doesn't clearly indicate transformation")
    else:
        feedback_parts.append("Transformer channel not found")

    # Check if transformer logic is configured (25 points - key criterion)
    if has_transformer:
        if has_transformer == "true":
            score += 25
            feedback_parts.append("Transformer logic detected in channel configuration")
        elif has_transformer == "possible":
            score += 10
            feedback_parts.append("Possible transformer configuration detected")
    else:
        feedback_parts.append("Transformer logic not confirmed in channel config")

    # Check output format (15 points)
    if output_format:
        if output_format.upper() == target_format.upper():
            score += 15
            feedback_parts.append(f"Output format matches target: {output_format}")
        else:
            score += 5
            feedback_parts.append(f"Output format detected: {output_format} (expected: {target_format})")
    else:
        feedback_parts.append("Output format not detected")

    # Check if transformed output exists (20 points - proves it works end-to-end)
    if transformed_output:
        score += 20
        feedback_parts.append("Transformed output files detected")

    # Determine pass/fail
    passed = score >= 70

    feedback = "\n".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
