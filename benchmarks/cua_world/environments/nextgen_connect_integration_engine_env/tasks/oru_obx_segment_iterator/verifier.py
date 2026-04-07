#!/usr/bin/env python3
"""
Verifier for oru_obx_segment_iterator task.

Verifies:
1. Channel creation and configuration
2. Successful processing of repeating segments (OBX)
3. Correct output format and content
4. Append mode configuration
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_oru_obx_segment_iterator(traj, env_info, task_info):
    """Verify ORU OBX iterator task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract results
    channel_found = result.get('channel_found', False)
    channel_name = result.get('channel_name', '')
    channel_status = result.get('channel_status', 'unknown')
    output_exists = result.get('output_exists', False)
    output_content = result.get('output_content', '')
    line_count = result.get('line_count', 0)
    append_test_passed = result.get('append_test_passed', False)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Channel Exists (15 pts)
    if channel_found:
        score += 15
        feedback_parts.append(f"Channel found: {channel_name}")
    else:
        feedback_parts.append("Channel not found")
        return {"passed": False, "score": 0, "feedback": "Channel 'Lab_Results_OBX_Extractor' not found"}

    # Criterion 2: Channel Started (10 pts)
    if channel_status == "STARTED":
        score += 10
        feedback_parts.append("Channel is STARTED")
    else:
        feedback_parts.append(f"Channel status is {channel_status} (expected STARTED)")

    # Criterion 3: Functional Test - Output Exists (20 pts)
    if output_exists:
        score += 20
        feedback_parts.append("Output file created successfully")
    else:
        feedback_parts.append("No output file generated from test message")

    # Criterion 4: Content Verification (30 pts)
    # Expect 8 lines for the first message. If append test ran, might be 9.
    # We look for key values from the first message.
    expected_values = [
        "6690-2", "WBC", "7.5",
        "789-8", "RBC", "4.82",
        "718-7", "HGB", "14.2",
        "777-3", "PLT", "245"
    ]
    
    content_matches = 0
    if output_content:
        for val in expected_values:
            if val in output_content:
                content_matches += 1
        
        match_percentage = content_matches / len(expected_values)
        if match_percentage >= 0.9:
            score += 30
            feedback_parts.append("Output content matches expected values")
        elif match_percentage >= 0.5:
            score += 15
            feedback_parts.append(f"Output content partially matches ({content_matches}/{len(expected_values)})")
        else:
            feedback_parts.append("Output content does not match expected values")
            
        # Check iteration count (at least 8 lines)
        if line_count >= 8:
            score += 10
            feedback_parts.append(f"Correctly iterated segments (found {line_count} lines)")
        else:
            feedback_parts.append(f"Failed to iterate all segments (found {line_count} lines, expected >= 8)")
    else:
        feedback_parts.append("Cannot verify content (empty output)")

    # Criterion 5: Append Mode (15 pts)
    if append_test_passed:
        score += 15
        feedback_parts.append("Append mode working correctly")
    elif output_exists:
        feedback_parts.append("Append mode check failed (file overwritten or not appended)")

    passed = score >= 60
    feedback = "\n".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": result
    }