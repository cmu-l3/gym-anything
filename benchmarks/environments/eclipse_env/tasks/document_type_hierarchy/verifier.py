#!/usr/bin/env python3
"""
Verifier for Document Type Hierarchy task.

Verifies that:
1. The 'handler_audit.txt' file exists and was created during the task.
2. It contains all 4 concrete implementations of IMessageHandler.
3. It correctly identifies indirect implementations (extends AbstractLoggingHandler).
4. It contains relevant Javadoc descriptions for the classes.
5. It does NOT contain abstract classes or the interface itself.
6. VLM confirms the user navigated using hierarchy tools.
"""

import json
import base64
import tempfile
import os
import logging
import sys

# Add workspace utils to path
sys.path.insert(0, '/workspace/utils')

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_document_type_hierarchy(traj, env_info, task_info):
    """
    Main verification function.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_classes = metadata.get('expected_classes', {})
    forbidden_classes = metadata.get('forbidden_classes', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Read Result JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}

    # 2. Check File Existence & Timestamp (20 points)
    if not result.get('file_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file 'handler_audit.txt' was not created."
        }
    
    if not result.get('file_created_during_task'):
        feedback_parts.append("Warning: File timestamp indicates it wasn't modified during task.")
        # We don't fail immediately but penalty applies
    else:
        score += 20
        feedback_parts.append("File created during task.")

    # 3. Decode and Analyze Content (60 points)
    try:
        content_b64 = result.get('file_content_b64', '')
        content = base64.b64decode(content_b64).decode('utf-8')
        content_lower = content.lower()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to decode file content: {e}"}

    # Check for forbidden classes (Abstract/Interface) - Penalty
    forbidden_found = False
    for forbidden in forbidden_classes:
        if forbidden in content:
            feedback_parts.append(f"Included forbidden abstract/interface: {forbidden}")
            forbidden_found = True
    
    if not forbidden_found:
        score += 10
        feedback_parts.append("Correctly excluded abstract classes/interfaces.")

    # Check for expected classes
    found_classes = 0
    indirect_found = 0
    
    for class_name, criteria in expected_classes.items():
        is_indirect = criteria['type'] == 'indirect'
        points = 15 if is_indirect else 10  # Indirect are worth more (harder to find)
        
        if class_name in content:
            # Check description keywords
            keywords = criteria.get('keywords', [])
            keyword_matches = sum(1 for k in keywords if k.lower() in content_lower)
            
            if keyword_matches >= 1:
                score += points
                found_classes += 1
                if is_indirect:
                    indirect_found += 1
                feedback_parts.append(f"Found {class_name} with description.")
            else:
                score += (points // 2)
                found_classes += 1
                feedback_parts.append(f"Found {class_name} but missing description keywords.")
        else:
            feedback_parts.append(f"Missing class: {class_name}")

    # 4. VLM Verification (20 points)
    # Check if the agent used Type Hierarchy or Quick Hierarchy
    vlm_score = 0
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Find implementations of IMessageHandler using Type Hierarchy",
            checklist_items=[
                "Eclipse 'Type Hierarchy' view is visible (tree structure)",
                "Or 'Quick Hierarchy' popup (Ctrl+T) is visible",
                "Agent navigated to source files of implementations",
                "Agent edited a text file"
            ]
        )
        
        if vlm_result:
            vlm_score = min(vlm_result.get('vlm_score', 0) * 0.2, 20)  # Scale to max 20 points
            if vlm_result.get('vlm_passed'):
                feedback_parts.append("VLM confirmed usage of hierarchy tools.")
            else:
                feedback_parts.append("VLM could not confirm usage of hierarchy tools.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if they found indirect classes, they likely used the tools
        if indirect_found == 2:
            vlm_score = 20
            feedback_parts.append("Indirect classes found (assuming tools were used).")

    total_score = min(score + int(vlm_score), 100)
    
    # Pass criteria: Must find at least one indirect class AND create the file
    passed = (result.get('file_exists') and 
              indirect_found >= 1 and 
              total_score >= 70)

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }