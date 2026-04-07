#!/usr/bin/env python3
"""
Verifier for Patient Chart Review task in OpenEMR

Robust verification with adversarial case handling:
1. Summary file must exist at expected location
2. Must be for correct patient (Mariana Hane, pid=11)
3. Must contain DOB
4. Must have medical problems section
5. Must be substantial (>500 chars)
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_patient_chart_review(traj, env_info, task_info):
    """
    Verify that patient chart review was completed.

    Scoring (100 points total):
    - File exists: 20 points
    - File length >= 500 chars: 15 points
    - Patient name correct: 20 points
    - DOB correct: 15 points
    - Has medical problems section: 15 points
    - Has medications section: 15 points

    Passing threshold: 70 points (file exists + name + DOB + problems)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 11)
    expected_fname = metadata.get('patient_fname', 'Mariana')
    expected_lname = metadata.get('patient_lname', 'Hane')
    expected_dob = metadata.get('patient_dob', '1978-06-24')
    min_file_length = metadata.get('min_file_length', 500)

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/patient_chart_review_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "file_exists": False,
            "file_length_ok": False,
            "patient_name_correct": False,
            "dob_correct": False,
            "has_problems": False,
            "has_medications": False
        }

        # Extract data
        file_exists = result.get('file_exists', False)
        file_length = result.get('file_length', 0)
        content_checks = result.get('content_checks', {})
        has_name = content_checks.get('has_patient_name', False)
        has_dob = content_checks.get('has_dob', False)
        has_problems = content_checks.get('has_problems_section', False)
        has_medications = content_checks.get('has_medications_section', False)
        file_preview = result.get('file_content_preview', '')

        logger.info(f"Result: exists={file_exists}, length={file_length}, name={has_name}, dob={has_dob}, problems={has_problems}")

        # CRITERION 1: File exists (20 points)
        if file_exists:
            score += 20
            subscores["file_exists"] = True
            feedback_parts.append("Summary file created")
        else:
            feedback_parts.append("CRITICAL: Summary file not found")
            return {
                "passed": False,
                "score": 0,
                "feedback": "Summary file not found at /home/ga/Desktop/patient_summary.txt",
                "subscores": subscores
            }

        # CRITERION 2: File length (15 points)
        if file_length >= min_file_length:
            score += 15
            subscores["file_length_ok"] = True
            feedback_parts.append(f"File length: {file_length} chars")
        else:
            feedback_parts.append(f"File too short: {file_length} chars (need {min_file_length})")

        # CRITERION 3: Patient name correct (20 points)
        if has_name:
            score += 20
            subscores["patient_name_correct"] = True
            feedback_parts.append(f"Patient: {expected_fname} {expected_lname}")
        else:
            # Double-check with our own regex on preview
            name_patterns = [
                rf'{expected_fname}.*{expected_lname}',
                rf'{expected_lname}.*{expected_fname}',
                rf'{expected_fname.lower()}.*{expected_lname.lower()}',
                rf'{expected_lname.lower()}.*{expected_fname.lower()}'
            ]
            for pattern in name_patterns:
                if re.search(pattern, file_preview, re.IGNORECASE):
                    score += 20
                    subscores["patient_name_correct"] = True
                    feedback_parts.append(f"Patient: {expected_fname} {expected_lname}")
                    break
            else:
                feedback_parts.append("Patient name not found or incorrect")

        # CRITERION 4: DOB correct (15 points)
        if has_dob:
            score += 15
            subscores["dob_correct"] = True
            feedback_parts.append(f"DOB: {expected_dob}")
        else:
            # Double-check with our own patterns
            dob_patterns = [
                r'1978.?06.?24',
                r'06.?24.?1978',
                r'June\s*24.*1978',
                r'24\s*June.*1978'
            ]
            for pattern in dob_patterns:
                if re.search(pattern, file_preview, re.IGNORECASE):
                    score += 15
                    subscores["dob_correct"] = True
                    feedback_parts.append(f"DOB: {expected_dob}")
                    break
            else:
                feedback_parts.append("DOB not found or incorrect")

        # CRITERION 5: Has medical problems section (15 points)
        if has_problems:
            score += 15
            subscores["has_problems"] = True
            feedback_parts.append("Medical problems documented")
        else:
            # Double-check
            problem_patterns = [
                r'problem',
                r'condition',
                r'diagnosis',
                r'medical\s+history',
                r'active\s+issues'
            ]
            for pattern in problem_patterns:
                if re.search(pattern, file_preview, re.IGNORECASE):
                    score += 15
                    subscores["has_problems"] = True
                    feedback_parts.append("Medical problems documented")
                    break
            else:
                feedback_parts.append("Medical problems section missing")

        # CRITERION 6: Has medications section (15 points)
        if has_medications:
            score += 15
            subscores["has_medications"] = True
            feedback_parts.append("Medications documented")
        else:
            # Double-check (but also acceptable to say "no medications")
            med_patterns = [
                r'medication',
                r'prescription',
                r'drug',
                r'no\s+active\s+medication',
                r'no\s+current\s+medication',
                r'NKDA',
                r'none\s+documented'
            ]
            for pattern in med_patterns:
                if re.search(pattern, file_preview, re.IGNORECASE):
                    score += 15
                    subscores["has_medications"] = True
                    feedback_parts.append("Medications documented")
                    break
            else:
                # Partial credit if they at least mentioned it's empty
                if re.search(r'(no|none|empty|n/a)', file_preview, re.IGNORECASE):
                    score += 10
                    feedback_parts.append("Medications section (partial)")
                else:
                    feedback_parts.append("Medications section missing")

        # Determine pass/fail
        # Must have: file (20) + name (20) + dob (15) + problems (15) = 70 minimum
        required_subscores = [
            subscores["file_exists"],
            subscores["patient_name_correct"],
            subscores["dob_correct"],
            subscores["has_problems"]
        ]
        passed = all(required_subscores) and score >= 70

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "file_length": file_length,
                "min_required": min_file_length,
                "patient_pid": expected_pid,
                "content_preview": file_preview[:200] + "..." if len(file_preview) > 200 else file_preview
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
