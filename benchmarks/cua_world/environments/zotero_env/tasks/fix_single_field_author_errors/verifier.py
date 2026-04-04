#!/usr/bin/env python3
"""
Verifier for fix_single_field_author_errors task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_fix_single_field_author_errors(traj, env_info, task_info):
    """
    Verify that the three authors have been converted to Two-Field mode 
    and have their names split correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Define targets and expectations
    targets = [
        {
            "key": "shannon",
            "name": "Shannon",
            "expected_last": "Shannon",
            "expected_first": "Claude E."
        },
        {
            "key": "turing",
            "name": "Turing",
            "expected_last": "Turing",
            "expected_first": "Alan"
        },
        {
            "key": "huffman",
            "name": "Huffman",
            "expected_last": "Huffman",
            "expected_first": "David A."
        }
    ]

    for t in targets:
        data = result.get(t["key"])
        
        if not data:
            feedback_parts.append(f"{t['name']}: Paper not found")
            continue

        field_mode = data.get("fieldMode")
        last_name = data.get("lastName", "").strip()
        first_name = data.get("firstName", "").strip()

        # Check Field Mode (0 = Two Field/Person, 1 = Single Field)
        # We want 0.
        if field_mode == 0:
            score += 20
            feedback_parts.append(f"{t['name']}: Mode correct (Two-field)")
            
            # Check Name Split (only check if mode is correct)
            # We check if names match expected values
            if last_name == t["expected_last"] and first_name == t["expected_first"]:
                score += 13  # 33.3 pts total per item approx
                feedback_parts.append(f"{t['name']}: Split correct")
            else:
                # Partial credit if they split it but maybe typo? 
                # Or if they just switched mode but didn't fix the text (e.g. Last="Shannon, Claude E.", First="")
                if last_name == t["expected_last"]:
                    score += 5
                    feedback_parts.append(f"{t['name']}: Last name correct, first name wrong")
                else:
                    feedback_parts.append(f"{t['name']}: Split incorrect ('{last_name}', '{first_name}')")
        else:
            feedback_parts.append(f"{t['name']}: Mode incorrect (Single-field)")

    # Normalize score to 100 max (3 * 33 = 99, add 1 free point or just round)
    if score >= 99:
        score = 100
        
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }