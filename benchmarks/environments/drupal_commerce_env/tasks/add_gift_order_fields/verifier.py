#!/usr/bin/env python3
"""
Verifier for add_gift_order_fields task.

Verifies:
1. Field storage configuration (fields exist in database).
2. Field instance configuration (fields attached to Order entity).
3. Field types (Text Long vs Boolean).
4. Field settings (Required status).
5. Form display settings (Fields are enabled).
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_gift_order_fields(traj, env_info, task_info):
    """
    Verify that gift message and gift wrap fields were correctly added to the Drupal Commerce order type.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Gift Message Field (Text, Long)
    # ---------------------------------------------------------
    # Storage check (15 pts)
    if result.get('msg_storage_exists'):
        score += 15
        feedback_parts.append("Gift Message storage created")
    else:
        feedback_parts.append("Gift Message field storage NOT found")

    # Instance check (15 pts)
    if result.get('msg_field_exists'):
        score += 15
        feedback_parts.append("Gift Message attached to Default Order")
    else:
        feedback_parts.append("Gift Message instance NOT found")

    # Type check (10 pts)
    # text_long is expected for "Text (plain, long)"
    msg_type = result.get('msg_type', '')
    if msg_type == 'text_long':
        score += 10
        feedback_parts.append("Gift Message type correct (Text, long)")
    elif result.get('msg_storage_exists'):
        # Partial credit if they made it a string (short text) or something else text-like
        if 'text' in msg_type or 'string' in msg_type:
            score += 5
            feedback_parts.append(f"Gift Message type incorrect but close: {msg_type} (expected text_long)")
        else:
            feedback_parts.append(f"Gift Message type incorrect: {msg_type}")

    # Not required check (5 pts)
    if result.get('msg_field_exists') and not result.get('msg_required'):
        score += 5
        feedback_parts.append("Gift Message is optional")
    elif result.get('msg_field_exists'):
        feedback_parts.append("Gift Message was marked as Required (should be optional)")

    # Form display check (5 pts)
    if result.get('msg_in_form'):
        score += 5
        feedback_parts.append("Gift Message enabled in form display")
    else:
        feedback_parts.append("Gift Message hidden in form display")

    # ---------------------------------------------------------
    # Criterion 2: Gift Wrap Field (Boolean)
    # ---------------------------------------------------------
    # Storage check (15 pts)
    if result.get('wrap_storage_exists'):
        score += 15
        feedback_parts.append("Gift Wrap storage created")
    else:
        feedback_parts.append("Gift Wrap field storage NOT found")

    # Instance check (15 pts)
    if result.get('wrap_field_exists'):
        score += 15
        feedback_parts.append("Gift Wrap attached to Default Order")
    else:
        feedback_parts.append("Gift Wrap instance NOT found")

    # Type check (10 pts)
    wrap_type = result.get('wrap_type', '')
    if wrap_type == 'boolean':
        score += 10
        feedback_parts.append("Gift Wrap type correct (Boolean)")
    elif result.get('wrap_storage_exists'):
        feedback_parts.append(f"Gift Wrap type incorrect: {wrap_type}")

    # Not required check (5 pts)
    if result.get('wrap_field_exists') and not result.get('wrap_required'):
        score += 5
        feedback_parts.append("Gift Wrap is optional")
    elif result.get('wrap_field_exists'):
        feedback_parts.append("Gift Wrap was marked as Required (should be optional)")

    # Form display check (5 pts)
    if result.get('wrap_in_form'):
        score += 5
        feedback_parts.append("Gift Wrap enabled in form display")
    else:
        feedback_parts.append("Gift Wrap hidden in form display")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    # To pass, must have at least created the fields (storage + instance)
    # Total points possible: 100
    # Mandatory checks for passing: Storage and Instance existence for BOTH fields
    
    essential_criteria = (
        result.get('msg_storage_exists') and 
        result.get('msg_field_exists') and 
        result.get('wrap_storage_exists') and 
        result.get('wrap_field_exists')
    )
    
    passed = score >= 60 and essential_criteria

    if not essential_criteria and score >= 60:
        feedback_parts.append("FAILED: Both fields must be fully created and attached to the order type.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }