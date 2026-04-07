#!/usr/bin/env python3
"""
Verifier for Add List Option task in OpenEMR

Verifies that a new 'Haitian' ethnicity option was added to the list_options table.

Scoring (100 points total):
- Option entry exists with 'Haitian' title: 30 points
- Option is in correct list (ethrace/ethnicity/race): 15 points
- Option is newly added during task: 20 points
- Option is active (enabled): 10 points
- Option has valid sequence number: 5 points
- VLM verification of navigation: 20 points

Pass threshold: 70 points (must have option created and correct list)
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_list_option(traj, env_info, task_info):
    """
    Verify that the Haitian ethnicity option was added to OpenEMR.
    
    Uses copy_from_env to read the exported result JSON from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_list_ids = metadata.get('expected_list_ids', ['ethrace', 'ethnicity', 'race'])
    expected_title = metadata.get('expected_title', 'Haitian')
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/add_list_option_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "option_exists": False,
            "correct_list": False,
            "newly_added": False,
            "is_active": False,
            "has_sequence": False,
            "vlm_verified": False
        }
        
        # Extract data from result
        option_found = result.get('option_found', False)
        new_option_added = result.get('new_option_added', False)
        initial_haitian = result.get('initial_haitian_count', 0)
        current_haitian = result.get('current_haitian_count', 0)
        initial_count = result.get('initial_option_count', 0)
        current_count = result.get('current_option_count', 0)
        option_details = result.get('option_details', {})
        
        logger.info(f"Result data: found={option_found}, new={new_option_added}")
        logger.info(f"Haitian count: initial={initial_haitian}, current={current_haitian}")
        logger.info(f"Option details: {option_details}")
        
        # CRITERION 1: Option exists with Haitian title (30 points)
        if option_found:
            option_title = option_details.get('title', '').strip()
            if expected_title.lower() in option_title.lower():
                score += 30
                subscores["option_exists"] = True
                feedback_parts.append(f"✓ Option with title '{option_title}' found in database")
            else:
                feedback_parts.append(f"✗ Option found but title mismatch: '{option_title}'")
        else:
            feedback_parts.append(f"✗ No option with '{expected_title}' title found in database")
        
        # CRITERION 2: Option is in correct list (15 points)
        list_id = option_details.get('list_id', '').strip()
        if list_id and list_id in expected_list_ids:
            score += 15
            subscores["correct_list"] = True
            feedback_parts.append(f"✓ Option added to correct list: '{list_id}'")
        elif list_id:
            feedback_parts.append(f"✗ Option in unexpected list: '{list_id}' (expected one of {expected_list_ids})")
        else:
            feedback_parts.append("✗ Could not determine which list the option was added to")
        
        # CRITERION 3: Option was newly added during task (20 points)
        # Check if Haitian count increased OR if total count increased
        if current_haitian > initial_haitian:
            score += 20
            subscores["newly_added"] = True
            feedback_parts.append(f"✓ New Haitian option added during task (count: {initial_haitian} → {current_haitian})")
        elif current_count > initial_count and option_found:
            # Partial credit if option exists and count increased
            score += 10
            feedback_parts.append(f"△ Option count increased ({initial_count} → {current_count}) but Haitian detection uncertain")
        else:
            if option_found and initial_haitian > 0:
                feedback_parts.append("✗ Haitian option existed before task - no new option added")
            else:
                feedback_parts.append("✗ No new options were added during task")
        
        # CRITERION 4: Option is active/enabled (10 points)
        active_value = option_details.get('active', '')
        if active_value == '1' or active_value == 1 or str(active_value).lower() == 'true':
            score += 10
            subscores["is_active"] = True
            feedback_parts.append("✓ Option is active (enabled)")
        elif active_value == '0' or active_value == 0:
            feedback_parts.append("✗ Option is inactive (disabled)")
        elif option_found:
            # If option found but active status unclear, give partial credit
            score += 5
            feedback_parts.append("△ Option active status unclear")
        
        # CRITERION 5: Option has valid sequence number (5 points)
        seq_value = option_details.get('sequence', '')
        if seq_value:
            try:
                seq_num = int(seq_value)
                if seq_num >= 0:
                    score += 5
                    subscores["has_sequence"] = True
                    feedback_parts.append(f"✓ Valid sequence number: {seq_num}")
            except (ValueError, TypeError):
                feedback_parts.append(f"△ Sequence value not a valid number: '{seq_value}'")
        elif option_found:
            feedback_parts.append("△ No sequence number set")
        
        # CRITERION 6: VLM verification of navigation (20 points)
        # Check trajectory screenshots to verify agent navigated correctly
        vlm_score = verify_navigation_via_vlm(traj, env_info)
        if vlm_score > 0:
            score += vlm_score
            subscores["vlm_verified"] = vlm_score >= 15
            if vlm_score >= 15:
                feedback_parts.append("✓ VLM confirmed navigation to Lists administration")
            else:
                feedback_parts.append("△ VLM partial confirmation of navigation")
        else:
            feedback_parts.append("△ VLM verification not performed or inconclusive")
        
        # Determine pass/fail
        # Must have option created AND in correct list to pass
        key_criteria_met = subscores["option_exists"] and subscores["correct_list"]
        passed = score >= 70 and key_criteria_met
        
        # Additional anti-gaming check: if option existed before, fail
        if initial_haitian > 0 and not subscores["newly_added"]:
            passed = False
            feedback_parts.append("⚠ ANTI-GAMING: Haitian option existed before task started")
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "option_details": option_details,
                "counts": {
                    "initial_haitian": initial_haitian,
                    "current_haitian": current_haitian,
                    "initial_total": initial_count,
                    "current_total": current_count
                }
            }
        }
        
    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - task export may have failed"
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def verify_navigation_via_vlm(traj, env_info):
    """
    Use VLM to verify agent navigated to Administration → Lists.
    
    Returns points (0-20) based on VLM verification.
    """
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        logger.warning("VLM query function not available")
        return 0
    
    try:
        # Get trajectory frames - sample across the trajectory
        frames = traj.get('frames', [])
        if not frames:
            logger.warning("No trajectory frames available")
            return 0
        
        # Sample frames from different parts of trajectory
        # Focus on middle and later frames where navigation should have occurred
        n_frames = len(frames)
        if n_frames >= 5:
            sample_indices = [
                n_frames // 4,      # Early
                n_frames // 2,      # Middle
                3 * n_frames // 4,  # Later
                n_frames - 1        # Final
            ]
        else:
            sample_indices = list(range(n_frames))
        
        sampled_frames = [frames[i] for i in sample_indices if i < n_frames]
        
        # VLM prompt to check for Lists administration interface
        vlm_prompt = """Analyze these screenshots from an OpenEMR session to determine if the user navigated to the Lists administration interface.

Look for evidence of:
1. OpenEMR Administration menu being accessed
2. A "Lists" or "List Options" management screen
3. A dropdown to select different lists (like Ethnicity, Race, etc.)
4. A form or table showing list options that can be edited/added
5. Any indication of adding a new item to a list

Respond in JSON format:
{
    "admin_menu_visible": true/false,
    "lists_interface_visible": true/false,
    "list_dropdown_visible": true/false,
    "add_option_form_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
        
        # Query VLM with sampled frames
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=sampled_frames
        )
        
        if not vlm_result.get('success'):
            logger.warning(f"VLM query failed: {vlm_result.get('error')}")
            return 0
        
        parsed = vlm_result.get('parsed', {})
        
        # Calculate VLM score based on what was verified
        vlm_score = 0
        
        if parsed.get('lists_interface_visible'):
            vlm_score += 10
        if parsed.get('admin_menu_visible'):
            vlm_score += 5
        if parsed.get('add_option_form_visible') or parsed.get('list_dropdown_visible'):
            vlm_score += 5
        
        # Adjust based on confidence
        confidence = parsed.get('confidence', 'low')
        if confidence == 'low' and vlm_score > 0:
            vlm_score = max(5, vlm_score // 2)
        
        logger.info(f"VLM verification result: {parsed}, score={vlm_score}")
        return min(vlm_score, 20)
        
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        return 0


if __name__ == "__main__":
    # Test harness for local testing
    print("Add List Option Verifier - Test Mode")
    print("This verifier requires the task environment to run properly.")