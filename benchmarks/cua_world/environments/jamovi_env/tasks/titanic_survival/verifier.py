#!/usr/bin/env python3
"""
Verifier for titanic_survival task (jamovi_env).

Parses the saved .omv file (a ZIP archive containing index.html with rendered
analysis output) and checks that the agent correctly configured two chi-square
tests of independence on the TitanicSurvival dataset.

Scoring rubric (100 points total, pass threshold 70):
  Criterion 1 (15 pts): File saved at the correct path
  Criterion 2 (10 pts): Valid .omv structure (ZIP with expected contents)
  Criterion 3 (25 pts): Chi-square for survived x passengerClass present
  Criterion 4 (25 pts): Chi-square for survived x sex present
  Criterion 5 (10 pts): Expected counts enabled in at least one analysis
  Criterion 6 (15 pts): Percentages enabled in at least one analysis
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

OMV_OUTPUT_FILE = "/home/ga/Documents/Jamovi/TitanicAnalysis.omv"
RESULT_JSON_PATH = "/tmp/titanic_survival_result.json"
PASS_THRESHOLD = 70


def verify_titanic_survival(traj, env_info, task_info):
    """
    Verify the titanic_survival task.

    Criteria:
      1. (15 pts) File saved at the correct path
      2. (10 pts) Valid .omv structure
      3. (25 pts) Chi-square for survived x passengerClass
      4. (25 pts) Chi-square for survived x sex
      5. (10 pts) Expected counts enabled
      6. (15 pts) Percentages enabled

    Pass threshold: 70/100
    """
    copy_from_env = env_info.get("copy_from_env")
    score = 0
    feedback_parts = []

    # ==================================================================
    # Output-existence gate: load the result JSON produced by export_result.sh
    # ==================================================================
    result = {}
    tmp_path = None
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_path = tmp.name
        tmp.close()

        if copy_from_env:
            try:
                copy_from_env(RESULT_JSON_PATH, tmp_path)
            except Exception as e:
                logger.warning(f"copy_from_env for result JSON failed: {e}, trying local")
                if not os.path.isfile(RESULT_JSON_PATH):
                    return {
                        "passed": False,
                        "score": 0,
                        "feedback": f"Could not retrieve result JSON: {e}",
                    }
                tmp_path = RESULT_JSON_PATH
        else:
            tmp_path = RESULT_JSON_PATH

        with open(tmp_path, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load result JSON from export_result.sh: {e}",
        }
    finally:
        if tmp_path and tmp_path != RESULT_JSON_PATH and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except Exception:
                pass

    # If the .omv file was not found at all, stop early
    if not result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output .omv file not found. The agent did not save the analysis.",
        }

    # ==================================================================
    # Criterion 1 (15 pts): File saved at the correct path
    # ==================================================================
    try:
        if result.get("file_exists", False):
            file_size = result.get("file_size_bytes", 0)
            if file_size > 0:
                score += 15
                feedback_parts.append(
                    f"C1: File saved ({file_size} bytes) (15/15)"
                )
            else:
                score += 5
                feedback_parts.append("C1: File exists but appears empty (5/15)")
        else:
            feedback_parts.append("C1: Output file not found (0/15)")
    except Exception as e:
        logger.error(f"Criterion 1 error: {e}", exc_info=True)
        feedback_parts.append(f"C1: Error checking file existence ({e}) (0/15)")

    # ==================================================================
    # Criterion 2 (10 pts): Valid .omv structure
    # ==================================================================
    try:
        valid_omv = result.get("valid_omv", False)
        has_index = result.get("has_index_html", False)

        if valid_omv and has_index:
            score += 10
            feedback_parts.append("C2: Valid .omv with index.html (10/10)")
        elif valid_omv:
            score += 7
            feedback_parts.append("C2: Valid .omv but index.html not found (7/10)")
        elif has_index:
            score += 5
            feedback_parts.append("C2: index.html found but .omv structure incomplete (5/10)")
        else:
            feedback_parts.append("C2: Invalid .omv structure (0/10)")
    except Exception as e:
        logger.error(f"Criterion 2 error: {e}", exc_info=True)
        feedback_parts.append(f"C2: Error checking .omv structure ({e}) (0/10)")

    # ==================================================================
    # Criterion 3 (25 pts): Chi-square for survived x passengerClass
    # ==================================================================
    try:
        has_chisq_class = result.get("has_chisq_class", False)

        if has_chisq_class:
            score += 25
            feedback_parts.append(
                "C3: Chi-square for survived x passengerClass found (25/25)"
            )
        else:
            # Partial credit: check if chi-square is present at all, and
            # if passengerClass and survived are mentioned in the HTML
            has_any_chisq = result.get("chisq_count", 0) > 0
            has_passengerclass = result.get("has_passengerclass", False)
            has_survived = result.get("has_survived", False)

            if has_any_chisq and has_passengerclass:
                score += 15
                feedback_parts.append(
                    "C3: Chi-square and passengerClass detected but not confirmed "
                    "together (15/25)"
                )
            elif has_any_chisq and has_survived:
                score += 10
                feedback_parts.append(
                    "C3: Chi-square present but passengerClass not found (10/25)"
                )
            elif has_any_chisq:
                score += 5
                feedback_parts.append(
                    "C3: Chi-square present but variables unclear (5/25)"
                )
            else:
                feedback_parts.append(
                    "C3: No chi-square for survived x passengerClass found (0/25)"
                )
    except Exception as e:
        logger.error(f"Criterion 3 error: {e}", exc_info=True)
        feedback_parts.append(f"C3: Error checking class chi-square ({e}) (0/25)")

    # ==================================================================
    # Criterion 4 (25 pts): Chi-square for survived x sex
    # ==================================================================
    try:
        has_chisq_sex = result.get("has_chisq_sex", False)

        if has_chisq_sex:
            score += 25
            feedback_parts.append(
                "C4: Chi-square for survived x sex found (25/25)"
            )
        else:
            # Partial credit
            has_any_chisq = result.get("chisq_count", 0) > 0
            has_sex = result.get("has_sex", False)
            has_survived = result.get("has_survived", False)

            if has_any_chisq and has_sex:
                score += 15
                feedback_parts.append(
                    "C4: Chi-square and sex detected but not confirmed "
                    "together (15/25)"
                )
            elif has_any_chisq and has_survived:
                score += 10
                feedback_parts.append(
                    "C4: Chi-square present but sex variable not found (10/25)"
                )
            elif has_any_chisq:
                score += 5
                feedback_parts.append(
                    "C4: Chi-square present but variables unclear (5/25)"
                )
            else:
                feedback_parts.append(
                    "C4: No chi-square for survived x sex found (0/25)"
                )
    except Exception as e:
        logger.error(f"Criterion 4 error: {e}", exc_info=True)
        feedback_parts.append(f"C4: Error checking sex chi-square ({e}) (0/25)")

    # ==================================================================
    # Criterion 5 (10 pts): Expected counts enabled
    # ==================================================================
    try:
        has_expected = result.get("has_expected_counts", False)

        if has_expected:
            score += 10
            feedback_parts.append("C5: Expected counts detected (10/10)")
        else:
            feedback_parts.append("C5: Expected counts not detected (0/10)")
    except Exception as e:
        logger.error(f"Criterion 5 error: {e}", exc_info=True)
        feedback_parts.append(f"C5: Error checking expected counts ({e}) (0/10)")

    # ==================================================================
    # Criterion 6 (15 pts): Percentages enabled
    # ==================================================================
    try:
        has_percentages = result.get("has_percentages", False)

        if has_percentages:
            score += 15
            feedback_parts.append("C6: Percentages detected (15/15)")
        else:
            feedback_parts.append("C6: Percentages not detected (0/15)")
    except Exception as e:
        logger.error(f"Criterion 6 error: {e}", exc_info=True)
        feedback_parts.append(f"C6: Error checking percentages ({e}) (0/15)")

    # ==================================================================
    # Final result
    # ==================================================================
    passed = score >= PASS_THRESHOLD
    feedback = " | ".join(feedback_parts)

    logger.info(
        f"Verification complete: score={score}/100, passed={passed} "
        f"(threshold={PASS_THRESHOLD})"
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
    }
