#!/usr/bin/env python3
"""Verifier for healthcare_record_pipeline_bugs task."""

import json
import re
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _strip_java_comments(src):
    """Strip // and /* */ comments so Javadoc fix-hints do not trigger verifier patterns."""
    src = re.sub(r'/\*.*?\*/', ' ', src, flags=re.DOTALL)  # block / Javadoc comments
    src = re.sub(r'//[^\n]*', '', src)                      # single-line comments
    return src


def verify_healthcare_record_pipeline_bugs(traj, env_info, task_info):
    """
    Verify that all three bugs in the healthcare pipeline were fixed.

    Scoring (100 points total):
    - Bug 1 fixed: Patient.equals()/hashCode() includes dateOfBirth (25 pts)
    - Bug 2 fixed: PatientRegistry.addRecord() re-throws validation exception (30 pts)
    - Bug 3 fixed: DiagnosticCoder.isValidCode() handles null safely (25 pts)
    - All tests pass (10 pts)
    - Test file unmodified (5 pts / -10 pts penalty)
    - VLM bonus: up to 5 pts

    Pass threshold: score >= 70 AND all tests pass
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/healthcare-pipeline')
    expected_tests = metadata.get('expected_test_count', 6)

    result = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        logger.debug(f"Could not read task_result.json: {e}")

    def copy_and_read(remote_path):
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(remote_path, tmp.name)
            with open(tmp.name, 'r', errors='replace') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception as e:
            logger.debug(f"Failed to read {remote_path}: {e}")
            return None

    score = 0
    feedback_parts = []

    tests_run    = result.get('tests_run', 0)
    tests_failed = result.get('tests_failed', 0)
    tests_error  = result.get('tests_error', 0)

    patient_src  = result.get('patient_source', '') or \
                   copy_and_read(f"{project_dir}/src/main/java/com/healthcare/Patient.java") or ''
    registry_src = result.get('registry_source', '') or \
                   copy_and_read(f"{project_dir}/src/main/java/com/healthcare/PatientRegistry.java") or ''
    coder_src    = result.get('coder_source', '') or \
                   copy_and_read(f"{project_dir}/src/main/java/com/healthcare/DiagnosticCoder.java") or ''

    # Strip comments so Javadoc fix-hints don't trigger fix-detection patterns
    patient_src_clean  = _strip_java_comments(patient_src)
    registry_src_clean = _strip_java_comments(registry_src)
    coder_src_clean    = _strip_java_comments(coder_src)

    # -----------------------------------------------------------------------
    # Criterion 1: Patient.equals()/hashCode() includes dateOfBirth (25 pts)
    # -----------------------------------------------------------------------
    try:
        # equals() must reference dateOfBirth — check method body only (comments stripped)
        equals_method_match = re.search(
            r'equals\s*\([^)]*\)\s*\{[^}]*\}',
            patient_src_clean, re.DOTALL
        )
        equals_body = equals_method_match.group(0) if equals_method_match else ''

        has_dob_in_equals = 'dateOfBirth' in equals_body or 'dob' in equals_body.lower()

        # hashCode() must reference dateOfBirth
        hashcode_match = re.search(
            r'hashCode\s*\(\s*\)\s*\{[^}]*\}',
            patient_src_clean, re.DOTALL
        )
        hashcode_body = hashcode_match.group(0) if hashcode_match else ''
        has_dob_in_hash = 'dateOfBirth' in hashcode_body or 'dob' in hashcode_body.lower()

        # No loose file-level fallback — method-body check is authoritative

        if has_dob_in_equals and has_dob_in_hash:
            score += 25
            feedback_parts.append("Patient.equals()/hashCode(): dateOfBirth included in both (Bug 1 fixed)")
        elif has_dob_in_equals:
            score += 15
            feedback_parts.append("Patient.equals(): dateOfBirth included but hashCode may still be name-only")
        elif has_dob_in_hash:
            score += 10
            feedback_parts.append("Patient.hashCode(): dateOfBirth included but equals() still name-only")
        else:
            feedback_parts.append("Patient.equals()/hashCode(): still name-only — same-name/different-DOB patients collide (Bug 1 not fixed)")
    except Exception as e:
        logger.debug(f"Criterion 1 check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 2: PatientRegistry.addRecord() re-throws exception (30 pts)
    # -----------------------------------------------------------------------
    try:
        # Check specifically whether the IllegalArgumentException catch block re-throws
        # (use comment-stripped source to avoid matching "// Missing: throw e;" hints)
        catch_iae_match = re.search(
            r'catch\s*\(\s*IllegalArgumentException[^)]*\)\s*\{([^}]*)\}',
            registry_src_clean, re.DOTALL
        )
        if catch_iae_match:
            catch_body = catch_iae_match.group(1)
            # Fix present if catch body contains an actual throw statement
            has_rethrow = bool(re.search(r'\bthrow\b', catch_body))
        else:
            # catch block removed entirely — also a valid fix
            has_rethrow = True

        if has_rethrow:
            score += 30
            feedback_parts.append("PatientRegistry.addRecord(): exception re-thrown to caller (Bug 2 fixed)")
        else:
            feedback_parts.append("PatientRegistry.addRecord(): exception still swallowed in catch block (Bug 2 not fixed)")
    except Exception as e:
        logger.debug(f"Criterion 2 check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 3: DiagnosticCoder.isValidCode() null-safe (25 pts)
    # -----------------------------------------------------------------------
    try:
        # Fix: must have null check before calling code.startsWith()
        # Use comment-stripped source so Javadoc fix-hints don't match
        has_null_check = bool(re.search(
            r'if\s*\(\s*code\s*==\s*null\s*\)',
            coder_src_clean
        )) or bool(re.search(
            r'code\s*==\s*null\s*\|\|',
            coder_src_clean
        )) or bool(re.search(
            r'Objects\.isNull\(code\)',
            coder_src_clean
        ))
        # Bug pattern: startsWith without preceding null check
        unguarded_startswith = bool(re.search(
            r'return\s+code\.startsWith',
            coder_src_clean
        )) and not has_null_check

        if has_null_check and not unguarded_startswith:
            score += 25
            feedback_parts.append("DiagnosticCoder.isValidCode(): null-safe (Bug 3 fixed)")
        elif has_null_check:
            score += 15
            feedback_parts.append("DiagnosticCoder: null check present but unguarded startsWith also found")
        else:
            feedback_parts.append("DiagnosticCoder.isValidCode(): no null check — NPE on null input (Bug 3 not fixed)")
    except Exception as e:
        logger.debug(f"Criterion 3 check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 4: All tests pass (10 pts)
    # -----------------------------------------------------------------------
    all_tests_pass = tests_run >= expected_tests and tests_failed == 0 and tests_error == 0
    if all_tests_pass:
        score += 10
        feedback_parts.append(f"All {tests_run} tests pass")
    elif tests_run > 0:
        feedback_parts.append(f"{tests_run} tests run, {tests_failed} failed, {tests_error} errors")
    else:
        feedback_parts.append("No test results found")

    # -----------------------------------------------------------------------
    # Criterion 5: Test file unmodified (5 pts)
    # -----------------------------------------------------------------------
    try:
        initial_cksum = result.get('test_checksum_initial', '')
        current_cksum = result.get('test_checksum_current', '')
        if initial_cksum and current_cksum:
            if initial_cksum == current_cksum:
                score += 5
                feedback_parts.append("Test file unmodified (correct)")
            else:
                score = max(0, score - 10)
                feedback_parts.append("WARNING: PatientRegistryTest.java was modified — penalty applied")
    except Exception:
        pass

    # -----------------------------------------------------------------------
    # VLM bonus (5 pts)
    # -----------------------------------------------------------------------
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from intellij_verification_utils import vlm_verify_intellij_task
        vlm_result = vlm_verify_intellij_task(
            traj, env_info,
            task_description=(
                "Fix three bugs in healthcare-pipeline: "
                "(1) Patient.equals()/hashCode() must include dateOfBirth, "
                "(2) PatientRegistry.addRecord() must propagate validation exceptions, "
                "(3) DiagnosticCoder.isValidCode() must return false (not throw NPE) for null input. "
                "All 6 tests in PatientRegistryTest must pass."
            ),
            checklist_items=[
                "IntelliJ IDEA is open with the healthcare-pipeline project",
                "Implementation files were edited",
                "Tests were run and all pass",
            ]
        )
        if vlm_result and vlm_result.get('vlm_passed'):
            score = min(score + 5, 100)
        if vlm_result:
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
    except Exception as e:
        logger.debug(f"VLM verification skipped: {e}")

    passed = score >= 70 and all_tests_pass
    if not all_tests_pass and score >= 60:
        feedback_parts.append("NOTE: Task incomplete — all 6 tests must pass with 0 failures")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "tests_run": tests_run,
            "tests_failed": tests_failed,
            "tests_error": tests_error,
        }
    }
