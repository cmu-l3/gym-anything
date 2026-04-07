#!/usr/bin/env python3
"""Verifier for Create Cohort Enrollment task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_cohort_enrollment(traj, env_info, task_info):
    """
    Verify creation of cohort, membership, and course sync enrollment.
    
    Scoring Strategy (100 points total):
    - Cohort exists with correct Name (15 pts)
    - Cohort exists with correct ID Number (10 pts)
    - Cohort created during task session (anti-gaming) (5 pts)
    - 4 Correct members added (8 pts each = 32 pts)
    - Exact member count is 4 (no extras) (8 pts)
    - Cohort sync enrollment method exists in CHEM101 (20 pts)
    - Enrollment role is Student (10 pts)
    
    Pass threshold: 65 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_members = set(metadata.get('target_members', ["jsmith", "mjones", "awilson", "bbrown"]))
    expected_cohort_name = metadata.get('target_cohort_name', "Biology Majors Fall 2025")
    expected_cohort_id = metadata.get('target_cohort_idnumber', "BIOMAJ-F25")

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_cohort_enrollment_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # 1. Verify Cohort Basics
        cohort_found = result.get('cohort_found', False)
        cohort_name = result.get('cohort_name', '')
        cohort_idnumber = result.get('cohort_idnumber', '')
        task_start = int(result.get('task_start_time', 0))
        cohort_created = int(result.get('cohort_timecreated', 0))

        if not cohort_found:
            feedback_parts.append("Cohort not found")
        else:
            # Check Name (15 pts)
            if expected_cohort_name.lower() in cohort_name.lower():
                score += 15
                feedback_parts.append("Cohort name correct")
            else:
                feedback_parts.append(f"Cohort name mismatch: '{cohort_name}'")

            # Check ID Number (10 pts)
            if expected_cohort_id == cohort_idnumber:
                score += 10
                feedback_parts.append("Cohort ID correct")
            else:
                feedback_parts.append(f"Cohort ID mismatch: '{cohort_idnumber}'")

            # Check Timestamp (5 pts)
            if cohort_created > task_start:
                score += 5
                feedback_parts.append("Cohort created during task")
            else:
                feedback_parts.append("Cohort appears to be pre-existing")

        # 2. Verify Members
        members_found = set(result.get('members', []))
        
        # Check specific members (8 pts each = 32 pts max)
        found_count = 0
        for member in expected_members:
            if member in members_found:
                score += 8
                found_count += 1
            else:
                feedback_parts.append(f"Missing member: {member}")
        
        if found_count == len(expected_members):
            feedback_parts.append("All required members found")
        
        # Check exact count (8 pts)
        member_count_total = int(result.get('member_count', 0))
        if member_count_total == 4:
            score += 8
            feedback_parts.append("Member count exact (4)")
        elif member_count_total > 4:
            feedback_parts.append(f"Too many members ({member_count_total})")
        else:
            feedback_parts.append(f"Too few members ({member_count_total})")

        # 3. Verify Enrollment Method
        enrol_found = result.get('enrol_method_found', False)
        role_archetype = result.get('enrol_role_archetype', '')

        if enrol_found:
            score += 20
            feedback_parts.append("Cohort sync enrollment configured")
            
            # Check Role (10 pts)
            if role_archetype == 'student':
                score += 10
                feedback_parts.append("Role set to Student")
            else:
                feedback_parts.append(f"Role mismatch (archetype: {role_archetype})")
        else:
            feedback_parts.append("Cohort sync enrollment NOT found in CHEM101")

        passed = score >= 65 and cohort_found and enrol_found

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}