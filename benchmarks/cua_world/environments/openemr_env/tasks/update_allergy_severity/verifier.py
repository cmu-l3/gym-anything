#!/usr/bin/env python3
"""
Verifier for Update Allergy Severity task in OpenEMR

Verifies that the agent correctly updated an existing allergy record:
1. Found the correct patient (Jayson Fadel, pid=3)
2. Edited the EXISTING Penicillin allergy (not created a duplicate)
3. Updated severity from 'mild' to 'severe'
4. Updated reaction to include 'anaphylaxis'
5. Record modification timestamp is after task start (anti-gaming)

Uses copy_from_env to read pre-exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_update_allergy_severity(traj, env_info, task_info):
    """
    Verify that the allergy severity was correctly updated.

    Scoring (100 points total):
    - Patient located correctly: 15 points
    - Allergy section accessed (record found): 15 points
    - Correct record edited (same ID, no duplicate): 20 points
    - Severity updated to severe: 25 points
    - Reaction includes anaphylaxis: 25 points

    Passing threshold: 75 points with severity_updated criterion met
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    expected_severity = metadata.get('expected_severity', 'severe')
    expected_reaction = metadata.get('expected_reaction', 'anaphylaxis')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/update_allergy_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "patient_located": False,
            "allergy_accessed": False,
            "correct_record_edited": False,
            "severity_updated": False,
            "reaction_updated": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        task_start = result.get('task_start_timestamp', 0)
        initial_state = result.get('initial_state', {})
        current_state = result.get('current_state', {})
        validation = result.get('validation', {})

        logger.info(f"Verification data loaded:")
        logger.info(f"  Patient PID: {patient_pid}")
        logger.info(f"  Initial state: {initial_state}")
        logger.info(f"  Current state: {current_state}")
        logger.info(f"  Validation flags: {validation}")

        # CRITERION 1: Patient located correctly (15 points)
        if patient_pid == expected_pid:
            score += 15
            subscores["patient_located"] = True
            feedback_parts.append(f"✅ Correct patient (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"❌ Wrong patient: expected pid={expected_pid}, got {patient_pid}")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Wrong patient targeted. Expected pid={expected_pid}",
                "subscores": subscores
            }

        # CRITERION 2: Allergy section accessed (15 points)
        allergy_found = current_state.get('allergy_found', False)
        if allergy_found:
            score += 15
            subscores["allergy_accessed"] = True
            feedback_parts.append("✅ Penicillin allergy record found")
        else:
            feedback_parts.append("❌ Penicillin allergy record not found")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 3: Correct record edited (20 points)
        # Check that same record was edited (not duplicated) and was modified during task
        same_record = validation.get('same_record_edited', False)
        record_modified = validation.get('record_modified_during_task', False)
        duplicate_created = validation.get('duplicate_created', False)

        if duplicate_created:
            # Penalty: agent created a new allergy instead of editing existing one
            feedback_parts.append("⚠️ Duplicate allergy created instead of editing existing record")
            # Give partial credit if the new record has correct values
        elif same_record and record_modified:
            score += 20
            subscores["correct_record_edited"] = True
            feedback_parts.append("✅ Existing record correctly edited (no duplicate)")
        elif same_record and not record_modified:
            # Same record but not modified - agent may have just viewed it
            score += 5
            feedback_parts.append("⚠️ Correct record found but modification timestamp not updated")
        else:
            feedback_parts.append("⚠️ Could not confirm same record was edited")
            # Give benefit of doubt if we can't verify

        # CRITERION 4: Severity updated to severe (25 points)
        severity_updated = validation.get('severity_updated_to_severe', False)
        current_severity = current_state.get('severity', '')
        initial_severity = initial_state.get('severity', '')

        if severity_updated:
            score += 25
            subscores["severity_updated"] = True
            feedback_parts.append(f"✅ Severity updated: '{initial_severity}' → '{current_severity}'")
        else:
            # Check manually if severity contains "severe"
            if current_severity and 'severe' in current_severity.lower():
                score += 25
                subscores["severity_updated"] = True
                feedback_parts.append(f"✅ Severity is now: '{current_severity}'")
            else:
                feedback_parts.append(f"❌ Severity not updated to severe (current: '{current_severity}')")

        # CRITERION 5: Reaction includes anaphylaxis (25 points)
        reaction_updated = validation.get('reaction_includes_anaphylaxis', False)
        current_reaction = current_state.get('reaction', '')
        initial_reaction = initial_state.get('reaction', '')

        if reaction_updated:
            score += 25
            subscores["reaction_updated"] = True
            feedback_parts.append(f"✅ Reaction updated to include anaphylaxis: '{current_reaction}'")
        else:
            # Check manually if reaction contains "anaphylaxis"
            if current_reaction and 'anaphylaxis' in current_reaction.lower():
                score += 25
                subscores["reaction_updated"] = True
                feedback_parts.append(f"✅ Reaction includes anaphylaxis: '{current_reaction}'")
            else:
                feedback_parts.append(f"❌ Reaction does not include anaphylaxis (current: '{current_reaction}')")

        # Apply duplicate penalty if applicable
        if duplicate_created:
            penalty = 15
            score = max(0, score - penalty)
            feedback_parts.append(f"⚠️ Penalty applied for creating duplicate: -{penalty} points")

        # Determine pass/fail
        # Must have severity updated and score >= 75
        passed = subscores["severity_updated"] and score >= 75

        # Additional VLM verification could be added here for trajectory analysis
        # This would verify the agent actually navigated through the allergy edit workflow

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "initial_state": initial_state,
                "current_state": current_state,
                "validation": validation
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found. The export script may not have run correctly.",
            "subscores": {
                "patient_located": False,
                "allergy_accessed": False,
                "correct_record_edited": False,
                "severity_updated": False,
                "reaction_updated": False
            }
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result file: {e}",
            "subscores": {
                "patient_located": False,
                "allergy_accessed": False,
                "correct_record_edited": False,
                "severity_updated": False,
                "reaction_updated": False
            }
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {
                "patient_located": False,
                "allergy_accessed": False,
                "correct_record_edited": False,
                "severity_updated": False,
                "reaction_updated": False
            }
        }


# For standalone testing
if __name__ == "__main__":
    # Mock test
    print("Verifier module loaded successfully")
    print("Function: verify_update_allergy_severity")
    print("Expected result file: /tmp/update_allergy_result.json")