#!/usr/bin/env python3
"""
Verifier for the tooth_growth_factorial task.

Parses the saved .omv file (a ZIP archive) and inspects index.html
to confirm the agent configured a two-way factorial ANOVA with the
required options (interaction, assumption checks, post-hoc, descriptives).

Scoring (100 points total):
  Criterion 1 (15 pts): .omv file saved at the correct path
  Criterion 2 (10 pts): Valid .omv structure (ZIP with index.html)
  Criterion 3 (25 pts): ANOVA present with correct DV (len) and factors (supp, dose)
  Criterion 4 (15 pts): Interaction term (supp x dose) included
  Criterion 5 (15 pts): Assumption checks (homogeneity + normality)
  Criterion 6 (10 pts): Post-hoc comparisons present
  Criterion 7 (10 pts): Descriptives table present

Pass threshold: 70 points
"""

import json
import logging
import os
import re
import tempfile
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

OMV_OUTPUT_PATH = "/home/ga/Documents/Jamovi/ToothGrowthAnalysis.omv"
RESULT_JSON_PATH = "/tmp/tooth_growth_factorial_result.json"
PASS_THRESHOLD = 70


def _extract_omv_html(omv_path):
    """Extract and read index.html from a .omv file (ZIP archive).

    Returns:
        tuple: (html_content, file_size, archive_files, error_string)
    """
    if not os.path.isfile(omv_path):
        return None, 0, [], f"File not found: {omv_path}"

    file_size = os.path.getsize(omv_path)

    tmpdir = tempfile.mkdtemp(prefix="omv_verify_")
    try:
        with zipfile.ZipFile(omv_path, "r") as zf:
            archive_files = zf.namelist()
            zf.extractall(tmpdir)

        index_path = os.path.join(tmpdir, "index.html")
        if not os.path.isfile(index_path):
            return None, file_size, archive_files, "index.html not found in .omv archive"

        with open(index_path, "r", encoding="utf-8-sig") as f:
            html_content = f.read()

        return html_content, file_size, archive_files, None

    except zipfile.BadZipFile:
        return None, file_size, [], "Invalid ZIP / .omv file"
    except Exception as exc:
        return None, file_size, [], f"Unexpected error: {exc}"


def _load_export_result():
    """Try to load the result JSON written by export_result.sh.

    Returns a dict or None.
    """
    try:
        if os.path.isfile(RESULT_JSON_PATH):
            with open(RESULT_JSON_PATH, "r", encoding="utf-8-sig") as f:
                return json.load(f)
    except Exception as exc:
        logger.warning("Could not load export result JSON: %s", exc)
    return None


def verify_tooth_growth_factorial(traj, env_info, task_info):
    """Verify that the agent created a proper factorial ANOVA analysis.

    This function is called by the Gym-Anything runner after the task
    completes. It returns a dict with keys: passed, score, feedback.
    """
    score = 0
    max_score = 100
    feedback_parts = []

    # -----------------------------------------------------------------
    # Obtain the .omv file — try copy_from_env first, then local path
    # -----------------------------------------------------------------
    omv_path = OMV_OUTPUT_PATH
    copy_from_env = env_info.get("copy_from_env")
    local_omv_path = None

    if copy_from_env:
        try:
            tmpdir = tempfile.mkdtemp(prefix="omv_verify_copy_")
            local_omv_path = os.path.join(tmpdir, "ToothGrowthAnalysis.omv")
            copy_from_env(OMV_OUTPUT_PATH, local_omv_path)
            omv_path = local_omv_path
        except Exception as exc:
            logger.warning("copy_from_env failed: %s, trying local path", exc)
            omv_path = OMV_OUTPUT_PATH

    # -----------------------------------------------------------------
    # Gate: does the .omv file exist at all?
    # -----------------------------------------------------------------
    if not os.path.isfile(omv_path):
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "No .omv output file found. The agent must save the analysis as "
                f"'{OMV_OUTPUT_PATH}'."
            ),
        }

    # =================================================================
    # Criterion 1 (15 pts): File saved at the correct path
    # =================================================================
    try:
        file_size = os.path.getsize(omv_path)
        if file_size > 0:
            score += 15
            feedback_parts.append(
                f"Criterion 1 (15/15): .omv file saved ({file_size} bytes)"
            )
        else:
            feedback_parts.append(
                "Criterion 1 (0/15): .omv file exists but is empty (0 bytes)"
            )
    except Exception as exc:
        feedback_parts.append(f"Criterion 1 (0/15): Error checking file: {exc}")

    # =================================================================
    # Criterion 2 (10 pts): Valid .omv structure (ZIP with index.html)
    # =================================================================
    html_content = None
    archive_files = []
    try:
        html_content, file_size, archive_files, error = _extract_omv_html(omv_path)

        if error:
            feedback_parts.append(
                f"Criterion 2 (0/10): Invalid .omv structure: {error}"
            )
        elif html_content and len(html_content) > 100:
            score += 10
            feedback_parts.append(
                f"Criterion 2 (10/10): Valid .omv structure "
                f"({len(archive_files)} files, index.html={len(html_content)} chars)"
            )
        elif html_content:
            score += 5
            feedback_parts.append(
                f"Criterion 2 (5/10): .omv has index.html but content is very small "
                f"({len(html_content)} chars)"
            )
        else:
            feedback_parts.append(
                "Criterion 2 (0/10): Could not extract index.html from .omv"
            )
    except Exception as exc:
        feedback_parts.append(f"Criterion 2 (0/10): Error parsing .omv: {exc}")

    # If we have no HTML content, also try the export result JSON
    # as a fallback source of analysis indicators
    export_result = _load_export_result()

    if not html_content:
        # Cannot proceed with HTML-based checks — return early
        feedback_parts.append(
            "Criteria 3-7: Skipped (no HTML content to analyze)"
        )
        return {
            "passed": score >= PASS_THRESHOLD,
            "score": score,
            "feedback": " | ".join(feedback_parts),
        }

    html_lower = html_content.lower()

    # =================================================================
    # Criterion 3 (25 pts): ANOVA present with correct DV and factors
    # =================================================================
    try:
        has_anova = bool(re.search(r'anova', html_lower))
        has_len = bool(re.search(r'\blen\b', html_lower))
        has_supp = bool(re.search(r'\bsupp\b', html_lower))
        has_dose = bool(re.search(r'\bdose\b', html_lower))

        if has_anova and has_len and has_supp and has_dose:
            score += 25
            feedback_parts.append(
                "Criterion 3 (25/25): ANOVA with correct DV ('len') and "
                "both factors ('supp', 'dose')"
            )
        elif has_anova and has_len and (has_supp or has_dose):
            score += 15
            missing = "dose" if not has_dose else "supp"
            feedback_parts.append(
                f"Criterion 3 (15/25): ANOVA with correct DV but "
                f"missing factor '{missing}'"
            )
        elif has_anova and has_len:
            score += 10
            feedback_parts.append(
                "Criterion 3 (10/25): ANOVA with correct DV but "
                "factors not detected in output"
            )
        elif has_anova:
            score += 5
            feedback_parts.append(
                "Criterion 3 (5/25): ANOVA detected but DV 'len' not found "
                "in output"
            )
        else:
            feedback_parts.append(
                "Criterion 3 (0/25): No ANOVA analysis detected in output"
            )
    except Exception as exc:
        feedback_parts.append(f"Criterion 3 (0/25): Error checking ANOVA: {exc}")

    # =================================================================
    # Criterion 4 (15 pts): Interaction term (supp x dose) included
    # =================================================================
    try:
        # jamovi renders interaction as supp ✻ dose, supp:dose, supp*dose,
        # or supp × dose in HTML output
        has_interaction = bool(
            re.search(r'supp\s*[\*:×✻\u2731]\s*dose', html_lower) or
            re.search(r'dose\s*[\*:×✻\u2731]\s*supp', html_lower)
        )

        # Also check the raw bytes for the unicode multiply sign
        # which may be encoded differently
        if not has_interaction:
            try:
                with open(
                    os.path.join(
                        tempfile.mkdtemp(prefix="omv_raw_"),
                        "dummy"
                    ).rsplit("/", 1)[0] + "/../index.html",
                    "rb"
                ) as _:
                    pass
            except Exception:
                pass

            # Broader pattern: look for both supp and dose near each other
            # with an operator between them (within ~20 chars)
            has_interaction = bool(
                re.search(r'supp.{1,20}dose', html_lower) and
                re.search(r'supp\s*.\s*dose', html_lower)
            )

        # Fallback: check export result JSON
        if not has_interaction and export_result:
            has_interaction = export_result.get("has_interaction", False)

        if has_interaction:
            score += 15
            feedback_parts.append(
                "Criterion 4 (15/15): Interaction term (supp x dose) detected"
            )
        else:
            # Partial credit if both factors are present (interaction may
            # exist but not be separately rendered in HTML)
            if has_supp and has_dose and has_anova:
                score += 5
                feedback_parts.append(
                    "Criterion 4 (5/15): Both factors present in ANOVA but "
                    "interaction term not explicitly detected in output"
                )
            else:
                feedback_parts.append(
                    "Criterion 4 (0/15): Interaction term not detected"
                )
    except Exception as exc:
        feedback_parts.append(f"Criterion 4 (0/15): Error checking interaction: {exc}")

    # =================================================================
    # Criterion 5 (15 pts): Assumption checks (homogeneity + normality)
    # =================================================================
    try:
        has_homogeneity = bool(
            re.search(r'homogeneity', html_lower) or
            re.search(r'levene', html_lower)
        )
        has_normality = bool(
            re.search(r'normality', html_lower) or
            re.search(r'shapiro', html_lower) or
            re.search(r'q-q\s*plot', html_lower)
        )

        # Fallback to export result
        if not has_homogeneity and export_result:
            has_homogeneity = export_result.get("has_homogeneity", False)
        if not has_normality and export_result:
            has_normality = export_result.get("has_normality", False)

        if has_homogeneity and has_normality:
            score += 15
            feedback_parts.append(
                "Criterion 5 (15/15): Both assumption checks present "
                "(homogeneity + normality)"
            )
        elif has_homogeneity or has_normality:
            score += 8
            present = "homogeneity" if has_homogeneity else "normality"
            missing = "normality" if has_homogeneity else "homogeneity"
            feedback_parts.append(
                f"Criterion 5 (8/15): Only {present} check found, "
                f"missing {missing}"
            )
        else:
            feedback_parts.append(
                "Criterion 5 (0/15): No assumption checks detected "
                "(homogeneity of variances / normality of residuals)"
            )
    except Exception as exc:
        feedback_parts.append(f"Criterion 5 (0/15): Error checking assumptions: {exc}")

    # =================================================================
    # Criterion 6 (10 pts): Post-hoc comparisons present
    # =================================================================
    try:
        has_posthoc = bool(
            re.search(r'post\s*hoc', html_lower) or
            re.search(r'post-hoc', html_lower) or
            re.search(r'tukey', html_lower) or
            re.search(r'bonferroni', html_lower) or
            re.search(r'games-howell', html_lower) or
            re.search(r'pairwise\s*comparisons', html_lower)
        )

        # Fallback to export result
        if not has_posthoc and export_result:
            has_posthoc = export_result.get("has_posthoc", False)

        if has_posthoc:
            score += 10
            feedback_parts.append(
                "Criterion 6 (10/10): Post-hoc comparisons detected"
            )
        else:
            feedback_parts.append(
                "Criterion 6 (0/10): No post-hoc comparisons detected"
            )
    except Exception as exc:
        feedback_parts.append(f"Criterion 6 (0/10): Error checking post-hoc: {exc}")

    # =================================================================
    # Criterion 7 (10 pts): Descriptives table present
    # =================================================================
    try:
        has_descriptives = bool(
            re.search(r'descriptive', html_lower) or
            re.search(r'group\s*descriptives', html_lower)
        )

        # Also look for mean/sd in table context (jamovi may render
        # descriptives without the word "descriptive")
        if not has_descriptives:
            has_mean_sd = bool(
                re.search(r'\bmean\b', html_lower) and
                re.search(r'\bsd\b', html_lower)
            )
            if has_mean_sd:
                has_descriptives = True

        # Fallback to export result
        if not has_descriptives and export_result:
            has_descriptives = export_result.get("has_descriptives", False)

        if has_descriptives:
            score += 10
            feedback_parts.append(
                "Criterion 7 (10/10): Descriptives table detected"
            )
        else:
            feedback_parts.append(
                "Criterion 7 (0/10): No descriptives table detected"
            )
    except Exception as exc:
        feedback_parts.append(f"Criterion 7 (0/10): Error checking descriptives: {exc}")

    # -----------------------------------------------------------------
    # Final result
    # -----------------------------------------------------------------
    passed = score >= PASS_THRESHOLD
    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
    }
