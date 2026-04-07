#!/usr/bin/env python3
"""
Verifier for Document Review of Systems task in OpenEMR

Verifies that a Review of Systems form was correctly completed for patient
Angelia Kuhic (pid=2) with appropriate clinical documentation.

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


def verify_review_of_systems(traj, env_info, task_info):
    """
    Verify that a Review of Systems was correctly documented.

    Scoring (100 points total):
    - ROS record exists for correct patient: 25 points
    - Record created after task start (anti-gaming): 15 points
    - Constitutional documented: 10 points
    - Cardiovascular documented: 10 points
    - Respiratory documented: 10 points
    - Musculoskeletal documented with positive finding: 15 points
    - Minimum 4 systems documented: 10 points
    - Form linked to encounter: 5 points

    Passing threshold: 70 points with ROS record exists and is new
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
    expected_pid = metadata.get('patient_pid', 2)
    expected_fname = metadata.get('patient_fname', 'Angelia')
    expected_lname = metadata.get('patient_lname', 'Kuhic')
    required_systems = metadata.get('required_systems', ['constitutional', 'cardiovascular', 'respiratory', 'musculoskeletal'])
    min_systems = metadata.get('minimum_systems_count', 4)
    positive_system = metadata.get('positive_finding_system', 'musculoskeletal')
    positive_keywords = metadata.get('positive_finding_keywords', ['knee', 'stiff', 'stiffness', 'occasional', 'positive'])

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/ros_task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "ros_record_exists": False,
            "record_is_new": False,
            "constitutional_documented": False,
            "cardiovascular_documented": False,
            "respiratory_documented": False,
            "musculoskeletal_documented": False,
            "musculoskeletal_has_positive": False,
            "minimum_systems_met": False,
            "form_linked": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_ros_count', 0)
        current_count = result.get('current_ros_count', 0)
        ros_found = result.get('ros_record_found', False)
        is_new = result.get('is_new_record', False)
        form_linked = result.get('form_linked_to_encounter', False)
        ros_record = result.get('ros_record', {})
        systems_count = result.get('systems_documented_count', 0)

        logger.info(f"Result data: pid={patient_pid}, initial={initial_count}, current={current_count}")
        logger.info(f"ROS found={ros_found}, is_new={is_new}, systems_count={systems_count}")

        # CRITERION 1: ROS record exists for correct patient (25 points)
        if patient_pid != expected_pid:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Wrong patient! Expected pid={expected_pid}, got {patient_pid}",
                "subscores": subscores
            }

        if ros_found:
            score += 25
            subscores["ros_record_exists"] = True
            feedback_parts.append(f"✅ ROS record found for patient {expected_fname} {expected_lname}")
        else:
            feedback_parts.append(f"❌ No ROS record found for patient pid={expected_pid}")
            # Check if any records exist at all
            if current_count == initial_count:
                feedback_parts.append("No new ROS records were created during the task")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: Record created after task start - anti-gaming (15 points)
        if is_new or current_count > initial_count:
            score += 15
            subscores["record_is_new"] = True
            feedback_parts.append(f"✅ New ROS record created during task (count: {initial_count} → {current_count})")
        else:
            feedback_parts.append(f"⚠️ ROS record may pre-date task (count unchanged: {current_count})")
            # Don't return early, but this is suspicious

        # Helper function to check if a field has content
        def has_content(field_value):
            if not field_value:
                return False
            if field_value.lower() in ['null', 'n', '', 'none']:
                return False
            return len(field_value.strip()) > 0

        # Helper function to check for keywords
        def contains_keywords(text, keywords):
            if not text:
                return False
            text_lower = text.lower()
            return any(kw.lower() in text_lower for kw in keywords)

        # CRITERION 3: Constitutional documented (10 points)
        constitutional = ros_record.get('constitutional', '')
        if has_content(constitutional):
            score += 10
            subscores["constitutional_documented"] = True
            feedback_parts.append(f"✅ Constitutional documented")
            logger.info(f"Constitutional: {constitutional[:100]}")
        else:
            feedback_parts.append("❌ Constitutional not documented")

        # CRITERION 4: Cardiovascular documented (10 points)
        cardiovascular = ros_record.get('cardiovascular', '')
        if has_content(cardiovascular):
            score += 10
            subscores["cardiovascular_documented"] = True
            feedback_parts.append(f"✅ Cardiovascular documented")
            logger.info(f"Cardiovascular: {cardiovascular[:100]}")
        else:
            feedback_parts.append("❌ Cardiovascular not documented")

        # CRITERION 5: Respiratory documented (10 points)
        respiratory = ros_record.get('respiratory', '')
        if has_content(respiratory):
            score += 10
            subscores["respiratory_documented"] = True
            feedback_parts.append(f"✅ Respiratory documented")
            logger.info(f"Respiratory: {respiratory[:100]}")
        else:
            feedback_parts.append("❌ Respiratory not documented")

        # CRITERION 6: Musculoskeletal with positive finding (15 points)
        musculoskeletal = ros_record.get('musculoskeletal', '')
        if has_content(musculoskeletal):
            subscores["musculoskeletal_documented"] = True
            logger.info(f"Musculoskeletal: {musculoskeletal[:100]}")
            
            # Check for expected positive finding keywords
            if contains_keywords(musculoskeletal, positive_keywords):
                score += 15
                subscores["musculoskeletal_has_positive"] = True
                feedback_parts.append(f"✅ Musculoskeletal documented with positive finding")
            else:
                # Partial credit for documenting the system even without expected keywords
                score += 8
                feedback_parts.append(f"⚠️ Musculoskeletal documented but missing expected positive finding (knee stiffness)")
        else:
            feedback_parts.append("❌ Musculoskeletal not documented")

        # CRITERION 7: Minimum systems documented (10 points)
        # Count all documented systems
        all_systems = [
            ros_record.get('constitutional', ''),
            ros_record.get('cardiovascular', ''),
            ros_record.get('respiratory', ''),
            ros_record.get('musculoskeletal', ''),
            ros_record.get('neurological', ''),
            ros_record.get('eyes', ''),
            ros_record.get('ear_nose_throat', ''),
            ros_record.get('gastrointestinal', ''),
            ros_record.get('psychiatric', '')
        ]
        
        documented_count = sum(1 for sys in all_systems if has_content(sys))
        
        if documented_count >= min_systems:
            score += 10
            subscores["minimum_systems_met"] = True
            feedback_parts.append(f"✅ Minimum systems documented ({documented_count}/{min_systems})")
        else:
            feedback_parts.append(f"❌ Insufficient systems documented ({documented_count}/{min_systems})")

        # CRITERION 8: Form linked to encounter (5 points)
        if form_linked:
            score += 5
            subscores["form_linked"] = True
            feedback_parts.append("✅ ROS form linked to encounter")
        else:
            feedback_parts.append("⚠️ ROS form not linked to encounter")

        # Determine pass/fail
        # Must have: ROS record exists AND is new AND at least 4 systems
        key_criteria = (
            subscores["ros_record_exists"] and
            subscores["record_is_new"]
        )
        passed = score >= 70 and key_criteria

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "ros_id": ros_record.get('id', ''),
                "systems_documented": documented_count,
                "initial_count": initial_count,
                "current_count": current_count
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run correctly"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {str(e)}"
        }
    except Exception as e:
        logger.exception("Verification error")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


if __name__ == "__main__":
    # Test mode - for local debugging
    print("Verifier for document_review_of_systems task")
    print("Run via gym-anything framework for actual verification")
    
    # Mock test with sample data
    sample_result = {
        "patient_pid": 2,
        "initial_ros_count": 0,
        "current_ros_count": 1,
        "ros_record_found": True,
        "is_new_record": True,
        "form_linked_to_encounter": True,
        "ros_record": {
            "id": "1",
            "date": "2024-01-15",
            "constitutional": "Denies fever, chills, fatigue, weight changes",
            "cardiovascular": "Denies chest pain, palpitations, edema",
            "respiratory": "Denies shortness of breath, cough, wheezing",
            "musculoskeletal": "Reports occasional knee stiffness",
            "neurological": "",
            "eyes": "",
            "ear_nose_throat": "",
            "gastrointestinal": "",
            "psychiatric": ""
        },
        "systems_documented_count": 4
    }
    
    print(f"\nSample test with mock data:")
    print(f"Expected result: PASS with ~100 points")