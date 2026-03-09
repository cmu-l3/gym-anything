#!/usr/bin/env python3
"""Verifier for legacy_exception_hardening task."""

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


def verify_legacy_exception_hardening(traj, env_info, task_info):
    """
    Verify that all four exception-handling bugs in the legacy service were fixed.

    Scoring (100 points total):
    - Bug 1 fixed: RecordParser.parseAmountCents() propagates NumberFormatException (20 pts)
    - Bug 2 fixed: EventLogger.log() propagates NullPointerException (25 pts)
    - Bug 3 fixed: ConfigLoader.load() declares throws IOException + try-with-resources (25 pts)
    - Bug 4 fixed: BatchProcessor.processAmounts() propagates parse errors (20 pts)
    - All tests pass (5 pts)
    - Test file unmodified (5 pts / -10 pts penalty)

    Pass threshold: score >= 70 AND all tests pass
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/legacy-service')
    expected_tests = metadata.get('expected_test_count', 9)

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

    parser_src = result.get('parser_source', '') or \
                 copy_and_read(f"{project_dir}/src/main/java/com/legacy/RecordParser.java") or ''
    logger_src = result.get('logger_source', '') or \
                 copy_and_read(f"{project_dir}/src/main/java/com/legacy/EventLogger.java") or ''
    config_src = result.get('config_source', '') or \
                 copy_and_read(f"{project_dir}/src/main/java/com/legacy/ConfigLoader.java") or ''
    batch_src  = result.get('batch_source', '') or \
                 copy_and_read(f"{project_dir}/src/main/java/com/legacy/BatchProcessor.java") or ''

    # Strip comments so Javadoc/inline fix-hints don't trigger fix-detection patterns
    parser_src_clean = _strip_java_comments(parser_src)
    logger_src_clean = _strip_java_comments(logger_src)
    config_src_clean = _strip_java_comments(config_src)
    batch_src_clean  = _strip_java_comments(batch_src)

    # -----------------------------------------------------------------------
    # Criterion 1: RecordParser no longer swallows NumberFormatException (20 pts)
    # -----------------------------------------------------------------------
    try:
        # Bug pattern: catch(NumberFormatException) with return 0L
        swallows_nfe = bool(re.search(
            r'catch\s*\(\s*NumberFormatException[^)]*\)[^}]*return\s+0',
            parser_src_clean, re.DOTALL
        ))
        # Fix: either no catch at all, or rethrows
        has_rethrow_nfe = bool(re.search(
            r'catch\s*\(\s*NumberFormatException[^)]*\)[^}]*throw',
            parser_src_clean, re.DOTALL
        ))
        no_nfe_catch = 'NumberFormatException' not in parser_src_clean or has_rethrow_nfe

        if not swallows_nfe:
            score += 20
            if has_rethrow_nfe:
                feedback_parts.append("RecordParser.parseAmountCents(): NumberFormatException re-thrown (Bug 1 fixed)")
            else:
                feedback_parts.append("RecordParser.parseAmountCents(): NFE no longer swallowed (Bug 1 fixed)")
        else:
            feedback_parts.append("RecordParser.parseAmountCents(): still catches NumberFormatException and returns 0 (Bug 1 not fixed)")
    except Exception as e:
        logger.debug(f"Criterion 1 check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 2: EventLogger.log() no longer swallows Exception (25 pts)
    # -----------------------------------------------------------------------
    try:
        # Bug pattern: broad catch(Exception) in the class (EventLogger only has one method
        # that could have a try/catch — the log() method).
        # Use comment-stripped source; the nested-brace extraction regex is unreliable here.
        broad_catch_in_log = bool(re.search(
            r'catch\s*\(\s*Exception\s+\w+\s*\)',
            logger_src_clean
        ))

        if not broad_catch_in_log:
            score += 25
            feedback_parts.append("EventLogger.log(): broad catch(Exception) removed — NPE propagates (Bug 2 fixed)")
        else:
            feedback_parts.append("EventLogger.log(): still has catch(Exception) — null eventType silently swallowed (Bug 2 not fixed)")
    except Exception as e:
        logger.debug(f"Criterion 2 check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 3: ConfigLoader.load() throws IOException + try-with-resources (25 pts)
    # -----------------------------------------------------------------------
    try:
        # Fix A: method signature must declare throws IOException
        has_throws_io = bool(re.search(
            r'load\s*\([^)]*\)\s*(?:throws\s+\w*IOException)',
            config_src_clean
        )) or bool(re.search(r'throws IOException', config_src_clean))

        # Fix B: try-with-resources (try (InputStream ...))
        has_try_with_resources = bool(re.search(r'try\s*\(', config_src_clean))

        # Bug pattern A: swallows IOException with catch
        swallows_io = bool(re.search(
            r'catch\s*\(\s*IOException[^)]*\)[^}]*System\.err',
            config_src_clean, re.DOTALL
        ))

        if has_throws_io and has_try_with_resources and not swallows_io:
            score += 25
            feedback_parts.append("ConfigLoader.load(): throws IOException declared, try-with-resources used (Bug 3 fully fixed)")
        elif has_throws_io and not swallows_io:
            score += 18
            feedback_parts.append("ConfigLoader.load(): throws IOException declared but try-with-resources not detected")
        elif has_try_with_resources and not swallows_io:
            score += 15
            feedback_parts.append("ConfigLoader.load(): try-with-resources used but throws IOException not in signature")
        elif not swallows_io:
            score += 10
            feedback_parts.append("ConfigLoader.load(): IOException no longer swallowed but signature/resource fixes unclear")
        else:
            feedback_parts.append("ConfigLoader.load(): IOException still swallowed; stream may also leak (Bug 3 not fixed)")
    except Exception as e:
        logger.debug(f"Criterion 3 check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 4: BatchProcessor no longer swallows parse exceptions (20 pts)
    # -----------------------------------------------------------------------
    try:
        # Bug pattern: catch(Exception) in processAmounts loop that does NOT rethrow
        # Use comment-stripped source to avoid "// Missing: throw new ..." comments triggering
        has_broad_catch_in_batch = bool(re.search(
            r'catch\s*\(\s*Exception\s+\w+\s*\)',
            batch_src_clean
        ))
        has_rethrow_in_batch = bool(re.search(
            r'catch[^}]*throw\s+(?:e|new)',
            batch_src_clean, re.DOTALL
        ))

        if not has_broad_catch_in_batch or has_rethrow_in_batch:
            score += 20
            feedback_parts.append("BatchProcessor.processAmounts(): parse errors now propagate to caller (Bug 4 fixed)")
        else:
            feedback_parts.append("BatchProcessor.processAmounts(): still swallows parse exceptions — corrupt records silently skipped (Bug 4 not fixed)")
    except Exception as e:
        logger.debug(f"Criterion 4 check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 5: All tests pass (5 pts)
    # -----------------------------------------------------------------------
    all_tests_pass = tests_run >= expected_tests and tests_failed == 0 and tests_error == 0
    if all_tests_pass:
        score += 5
        feedback_parts.append(f"All {tests_run} tests pass")
    elif tests_run > 0:
        feedback_parts.append(f"{tests_run} tests run, {tests_failed} failed, {tests_error} errors")
    else:
        feedback_parts.append("No test results found")

    # -----------------------------------------------------------------------
    # Criterion 6: Test file unmodified (5 pts)
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
                feedback_parts.append("WARNING: ExceptionHandlingTest.java was modified — penalty applied")
    except Exception:
        pass

    # -----------------------------------------------------------------------
    # VLM bonus (included in 100 pts budget via partial credit above)
    # -----------------------------------------------------------------------
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from intellij_verification_utils import vlm_verify_intellij_task
        vlm_result = vlm_verify_intellij_task(
            traj, env_info,
            task_description=(
                "Fix four exception-handling bugs in legacy-service per the AUDIT_REPORT.md: "
                "(1) RecordParser must not swallow NumberFormatException, "
                "(2) EventLogger.log() must not catch Exception broadly, "
                "(3) ConfigLoader.load() must declare throws IOException and use try-with-resources, "
                "(4) BatchProcessor must propagate parse errors. "
                "All 9 tests in ExceptionHandlingTest must pass."
            ),
            checklist_items=[
                "IntelliJ IDEA is open with the legacy-service project",
                "AUDIT_REPORT.md was reviewed",
                "Implementation files were edited in IntelliJ",
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
        feedback_parts.append("NOTE: Task incomplete — all 9 tests must pass with 0 failures")

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
