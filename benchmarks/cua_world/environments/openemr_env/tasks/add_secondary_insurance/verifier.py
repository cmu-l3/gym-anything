#!/usr/bin/env python3
"""
Verifier for Add Secondary Insurance task in OpenEMR

Verifies that secondary insurance was correctly added while preserving primary insurance.

Scoring (100 points total):
- Secondary insurance record saved: 20 points
- Correct insurance type (secondary): 15 points
- Policy number correct: 20 points
- Group number correct: 15 points
- Subscriber relationship correct: 10 points
- Primary insurance preserved: 10 points
- VLM trajectory verification: 10 points

Pass threshold: 70 points with record saved and primary preserved
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_secondary_insurance(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that secondary insurance was correctly added to patient record.
    
    Args:
        traj: Trajectory data with frames and episode info
        env_info: Environment info including copy_from_env function
        task_info: Task metadata with expected values
    
    Returns:
        Dict with passed, score, feedback, and subscores
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task completion"
        }
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_policy = metadata.get('expected_policy_number', 'SEC-2024-889712')
    expected_group = metadata.get('expected_group_number', 'MEDIGAP-F')
    expected_subscriber = metadata.get('expected_subscriber_relationship', 'self')
    expected_type = metadata.get('expected_insurance_type', 'secondary')
    expected_company = metadata.get('expected_insurance_company', 'Blue Cross Blue Shield')
    patient_pid = metadata.get('patient_pid', 6)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    subscores = {
        "record_saved": False,
        "correct_type": False,
        "policy_correct": False,
        "group_correct": False,
        "subscriber_correct": False,
        "primary_preserved": False,
        "newly_added": False,
        "vlm_verification": False
    }
    
    # Copy result JSON from container
    result = None
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/secondary_insurance_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to copy result file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read verification data: {e}",
            "subscores": subscores
        }
    
    if not result:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No verification data available",
            "subscores": subscores
        }
    
    # Extract data from result
    secondary_found = result.get('secondary_found', False)
    newly_added = result.get('newly_added', False)
    primary_preserved = result.get('primary_preserved', False)
    insurance = result.get('insurance', {})
    validation = result.get('validation', {})
    initial_counts = result.get('initial_counts', {})
    current_counts = result.get('current_counts', {})
    
    logger.info(f"Secondary found: {secondary_found}, Newly added: {newly_added}")
    logger.info(f"Insurance data: {insurance}")
    logger.info(f"Validation: {validation}")
    
    # CRITERION 1: Secondary insurance record saved (20 points)
    if secondary_found:
        score += 20
        subscores["record_saved"] = True
        feedback_parts.append("✅ Secondary insurance record exists")
    else:
        feedback_parts.append("❌ No secondary insurance record found")
        # Check if policy was added but as wrong type
        if validation.get('policy_exists_any_type', False):
            feedback_parts.append("⚠️ Policy number found but may be wrong insurance type")
    
    # CRITERION 2: Correct insurance type - secondary (15 points)
    if validation.get('type_correct', False):
        score += 15
        subscores["correct_type"] = True
        feedback_parts.append("✅ Insurance type correctly set to 'secondary'")
    elif secondary_found:
        actual_type = insurance.get('type', '')
        feedback_parts.append(f"❌ Wrong insurance type: expected 'secondary', got '{actual_type}'")
    
    # CRITERION 3: Policy number correct (20 points)
    if validation.get('policy_correct', False):
        score += 20
        subscores["policy_correct"] = True
        feedback_parts.append(f"✅ Policy number correct: {expected_policy}")
    elif secondary_found:
        actual_policy = insurance.get('policy_number', '')
        feedback_parts.append(f"❌ Policy number mismatch: expected '{expected_policy}', got '{actual_policy}'")
    
    # CRITERION 4: Group number correct (15 points)
    if validation.get('group_correct', False):
        score += 15
        subscores["group_correct"] = True
        feedback_parts.append(f"✅ Group number correct: {expected_group}")
    elif secondary_found:
        actual_group = insurance.get('group_number', '')
        feedback_parts.append(f"❌ Group number mismatch: expected '{expected_group}', got '{actual_group}'")
    
    # CRITERION 5: Subscriber relationship correct (10 points)
    if validation.get('subscriber_correct', False):
        score += 10
        subscores["subscriber_correct"] = True
        feedback_parts.append("✅ Subscriber relationship correctly set to 'self'")
    elif secondary_found:
        actual_subscriber = insurance.get('subscriber_relationship', '')
        feedback_parts.append(f"❌ Subscriber mismatch: expected 'self', got '{actual_subscriber}'")
    
    # CRITERION 6: Primary insurance preserved (10 points) - CRITICAL
    if primary_preserved:
        score += 10
        subscores["primary_preserved"] = True
        feedback_parts.append("✅ Primary insurance preserved (not deleted or overwritten)")
    else:
        feedback_parts.append("❌ CRITICAL: Primary insurance was deleted or overwritten!")
        # This is a serious error - reduce score significantly
        score = max(0, score - 20)
    
    # CRITERION 7: Newly added during task (anti-gaming check)
    if newly_added:
        subscores["newly_added"] = True
        feedback_parts.append("✅ Insurance was newly added during this task")
    elif secondary_found:
        feedback_parts.append("⚠️ Secondary insurance may have existed before task started")
        # Reduce score slightly for potential gaming
        score = max(0, score - 10)
    
    # CRITERION 8: VLM trajectory verification (10 points)
    vlm_score = verify_with_vlm(traj, env_info, expected_policy, expected_company)
    if vlm_score > 0:
        score += vlm_score
        subscores["vlm_verification"] = True
        feedback_parts.append("✅ VLM verified insurance workflow in trajectory")
    else:
        feedback_parts.append("⚠️ VLM could not verify workflow (may still be correct)")
    
    # Determine pass/fail
    # Must have: record saved, primary preserved, and score >= 70
    key_criteria_met = subscores["record_saved"] and subscores["primary_preserved"]
    passed = score >= 70 and key_criteria_met
    
    # Summary
    initial_sec = initial_counts.get('secondary', 0)
    current_sec = current_counts.get('secondary', 0)
    feedback_parts.insert(0, f"Secondary insurance count: {initial_sec} → {current_sec}")
    
    return {
        "passed": passed,
        "score": min(100, score),  # Cap at 100
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "patient_pid": patient_pid,
            "expected_policy": expected_policy,
            "actual_policy": insurance.get('policy_number', ''),
            "expected_group": expected_group,
            "actual_group": insurance.get('group_number', ''),
            "insurance_type": insurance.get('type', ''),
            "company_name": insurance.get('company_name', ''),
            "primary_preserved": primary_preserved,
            "newly_added": newly_added
        }
    }


def verify_with_vlm(traj: Dict[str, Any], env_info: Dict[str, Any], 
                    expected_policy: str, expected_company: str) -> int:
    """
    Use VLM to verify the agent performed the insurance workflow correctly.
    
    Checks trajectory frames (not just final screenshot) to verify:
    - Patient search was performed
    - Demographics/Insurance section was accessed
    - Secondary insurance form was filled
    
    Returns:
        int: Points earned (0-10)
    """
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        logger.warning("VLM query function not available")
        return 0
    
    # Try to get trajectory frames
    try:
        # Sample frames from trajectory
        frames = traj.get('frames', [])
        if not frames:
            logger.warning("No trajectory frames available")
            return 0
        
        # Sample 5 frames evenly across trajectory
        num_frames = len(frames)
        if num_frames <= 5:
            sample_indices = list(range(num_frames))
        else:
            step = num_frames // 5
            sample_indices = [i * step for i in range(5)]
        
        sampled_frames = [frames[i] for i in sample_indices if i < len(frames)]
        
        # Also get final frame
        final_frame = frames[-1] if frames else None
        
    except Exception as e:
        logger.warning(f"Could not extract trajectory frames: {e}")
        return 0
    
    # VLM verification prompt
    verification_prompt = f"""You are verifying if a computer agent successfully added secondary insurance to a patient's record in OpenEMR (Electronic Health Records system).

TASK: Add secondary insurance (Blue Cross Blue Shield, policy {expected_policy}) to patient Jacklyn Kulas.

Examine these trajectory screenshots and determine:
1. Did the agent navigate to a patient record (search or demographics view)?
2. Did the agent access an insurance or demographics section?
3. Did the agent appear to fill in insurance form fields?
4. Is there any indication of secondary insurance being added (not primary)?
5. Did the agent appear to save/submit the form?

Look for:
- Patient search screens
- Demographics or insurance editing screens
- Form fields with "secondary" insurance designation
- Policy number fields
- Save/submit buttons being clicked

Respond in JSON format:
{{
    "patient_record_accessed": true/false,
    "insurance_section_found": true/false,
    "form_fields_filled": true/false,
    "secondary_indicated": true/false,
    "form_submitted": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}}
"""

    try:
        # Query VLM with sampled frames
        images_to_check = sampled_frames
        if final_frame and final_frame not in sampled_frames:
            images_to_check.append(final_frame)
        
        vlm_result = query_vlm(
            prompt=verification_prompt,
            images=images_to_check
        )
        
        if not vlm_result.get('success', False):
            logger.warning(f"VLM query failed: {vlm_result.get('error', 'Unknown error')}")
            return 0
        
        parsed = vlm_result.get('parsed', {})
        
        # Score based on VLM findings
        vlm_points = 0
        
        if parsed.get('patient_record_accessed', False):
            vlm_points += 2
        if parsed.get('insurance_section_found', False):
            vlm_points += 2
        if parsed.get('form_fields_filled', False):
            vlm_points += 2
        if parsed.get('secondary_indicated', False):
            vlm_points += 2
        if parsed.get('form_submitted', False):
            vlm_points += 2
        
        # Adjust based on confidence
        confidence = parsed.get('confidence', 'low')
        if confidence == 'low':
            vlm_points = vlm_points // 2
        elif confidence == 'medium':
            vlm_points = int(vlm_points * 0.75)
        
        logger.info(f"VLM verification: {parsed}, points: {vlm_points}")
        return min(10, vlm_points)
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        return 0


# Alternative entry point for testing
if __name__ == "__main__":
    # Test with mock data
    mock_result = {
        "secondary_found": True,
        "newly_added": True,
        "primary_preserved": True,
        "insurance": {
            "type": "secondary",
            "policy_number": "SEC-2024-889712",
            "group_number": "MEDIGAP-F",
            "subscriber_relationship": "self"
        },
        "validation": {
            "policy_correct": True,
            "group_correct": True,
            "type_correct": True,
            "subscriber_correct": True
        },
        "initial_counts": {"primary": 1, "secondary": 0},
        "current_counts": {"primary": 1, "secondary": 1}
    }
    
    print("Mock verification test:")
    print(f"Secondary found: {mock_result['secondary_found']}")
    print(f"Primary preserved: {mock_result['primary_preserved']}")
    print(f"Validation: {mock_result['validation']}")