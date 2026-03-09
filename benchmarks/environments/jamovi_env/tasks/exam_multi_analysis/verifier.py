#!/usr/bin/env python3
"""
Verifier for exam_multi_analysis task (jamovi_env).

Parses the saved .omv file (a ZIP archive) and inspects the contents
(index.html with rendered analysis output, plus internal metadata) to verify
that the agent correctly configured Descriptive Statistics (split by Gender),
Independent Samples T-Test, and Correlation Matrix analyses on ExamAnxiety.csv.

Scoring rubric (100 points total, pass threshold 70):
  Criterion 1 (15 pts): File saved at correct path
  Criterion 2 (10 pts): File is a valid .omv (ZIP with expected structure)
  Criterion 3 (25 pts): Descriptives analysis with Exam/Revise/Anxiety split by Gender
  Criterion 4 (25 pts): Independent Samples T-Test with Exam as DV, Gender as grouping var
  Criterion 5 (25 pts): Correlation Matrix with Exam, Revise, Anxiety
"""

import json
import logging
import os
import re
import tempfile
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

OMV_OUTPUT_FILE = "/home/ga/Documents/Jamovi/ExamAnalysis.omv"
RESULT_JSON = "/tmp/exam_multi_analysis_result.json"
PASS_THRESHOLD = 70

EXPECTED_ANALYSIS_VARS = {"Exam", "Revise", "Anxiety"}
GROUPING_VAR = "Gender"
TTEST_DV = "Exam"


def _extract_omv_file(omv_path, copy_from_env=None):
    """Extract .omv ZIP archive and return (temp_dir, extract_dir, file_size) or raise."""
    temp_dir = tempfile.mkdtemp(prefix="jamovi_exam_verify_")

    # If copy_from_env is available, copy the file from the VM first
    local_omv = os.path.join(temp_dir, "ExamAnalysis.omv")
    if copy_from_env:
        try:
            copy_from_env(omv_path, local_omv)
        except Exception as e:
            logger.warning(f"copy_from_env failed: {e}, trying local path")
            local_omv = omv_path
    else:
        local_omv = omv_path

    if not os.path.isfile(local_omv):
        raise FileNotFoundError(f"OMV output file not found: {omv_path}")

    file_size = os.path.getsize(local_omv)
    extract_dir = os.path.join(temp_dir, "extracted")
    os.makedirs(extract_dir, exist_ok=True)

    with zipfile.ZipFile(local_omv, "r") as zf:
        zf.extractall(extract_dir)

    return temp_dir, extract_dir, file_size


def _read_index_html(extract_dir):
    """Locate and read index.html from the extracted .omv archive."""
    index_path = os.path.join(extract_dir, "index.html")
    if not os.path.exists(index_path):
        # Walk the extracted tree
        for root, dirs, files in os.walk(extract_dir):
            if "index.html" in files:
                index_path = os.path.join(root, "index.html")
                break

    if not os.path.exists(index_path):
        return None

    with open(index_path, "r", encoding="utf-8-sig") as f:
        return f.read()


def _read_result_json():
    """Read the export_result.sh output JSON as supplementary evidence."""
    if not os.path.exists(RESULT_JSON):
        return {}
    try:
        with open(RESULT_JSON, "r", encoding="utf-8-sig") as f:
            return json.load(f)
    except Exception:
        return {}


def _check_descriptives_in_html(html_content):
    """
    Check if Descriptives analysis is present with correct variables and split.
    Returns (score, feedback_parts) where score is 0-25.
    """
    score = 0
    feedback = []
    html_lower = html_content.lower()

    # Check for Descriptives analysis presence
    desc_patterns = [
        "descriptives",
        "descriptive statistics",
        "jmv-descriptives",
        "jmvconnect-descriptives",
    ]
    has_descriptives = any(pat in html_lower for pat in desc_patterns)

    if not has_descriptives:
        feedback.append("Descriptives: analysis NOT found in output")
        return score, feedback

    score += 5
    feedback.append("Descriptives: analysis found in output")

    # Check that the analysis variables (Exam, Revise, Anxiety) appear
    found_vars = set()
    for var in EXPECTED_ANALYSIS_VARS:
        if var.lower() in html_lower:
            found_vars.add(var)

    if len(found_vars) >= 3:
        score += 8
        feedback.append(f"Descriptives: all 3 variables found ({', '.join(sorted(found_vars))})")
    elif len(found_vars) >= 2:
        score += 4
        feedback.append(
            f"Descriptives: {len(found_vars)}/3 variables found ({', '.join(sorted(found_vars))})"
        )
    else:
        feedback.append(f"Descriptives: only {len(found_vars)}/3 expected variables found")

    # Check for Gender split
    if GROUPING_VAR.lower() in html_lower:
        # Look for evidence of split: "Male" and "Female" appearing in descriptives context
        has_male = "male" in html_lower
        has_female = "female" in html_lower
        if has_male and has_female:
            score += 8
            feedback.append("Descriptives: split by Gender detected (Male and Female groups found)")
        else:
            score += 4
            feedback.append("Descriptives: Gender variable found but Male/Female groups not confirmed")
    else:
        feedback.append("Descriptives: Gender split not detected")

    # Check for statistics (mean, median, sd, min, max)
    stats_keywords = ["mean", "median", "standard deviation", "std. deviation",
                      "minimum", "maximum", "std.dev"]
    stats_found = sum(1 for kw in stats_keywords if kw in html_lower)
    if stats_found >= 3:
        score += 4
        feedback.append(f"Descriptives: {stats_found} statistic types detected")
    elif stats_found >= 1:
        score += 2
        feedback.append(f"Descriptives: {stats_found} statistic types detected (expected 3+)")
    else:
        feedback.append("Descriptives: no statistic keywords detected")

    return score, feedback


def _check_ttest_in_html(html_content):
    """
    Check if Independent Samples T-Test is present with correct DV and grouping variable.
    Returns (score, feedback_parts) where score is 0-25.
    """
    score = 0
    feedback = []
    html_lower = html_content.lower()

    # Check for T-Test analysis presence
    ttest_patterns = [
        "independent samples t-test",
        "independent-samples t-test",
        "independentsamples",
        "jmv-ttestis",
        "ttestis",
    ]
    has_ttest = any(pat in html_lower for pat in ttest_patterns)

    if not has_ttest:
        # Looser check: just "t-test" might appear
        if "t-test" in html_lower:
            score += 3
            feedback.append("T-Test: generic t-test reference found but not confirmed as Independent Samples")
        else:
            feedback.append("T-Test: analysis NOT found in output")
        return score, feedback

    score += 8
    feedback.append("T-Test: Independent Samples T-Test found in output")

    # Check that Exam is the dependent variable
    # In jamovi output, the DV name typically appears in the results table
    if TTEST_DV.lower() in html_lower:
        score += 7
        feedback.append(f"T-Test: dependent variable '{TTEST_DV}' found in output")
    else:
        feedback.append(f"T-Test: dependent variable '{TTEST_DV}' not found in output")

    # Check that Gender is the grouping variable
    if GROUPING_VAR.lower() in html_lower:
        has_male = "male" in html_lower
        has_female = "female" in html_lower
        if has_male and has_female:
            score += 7
            feedback.append("T-Test: grouping variable Gender with Male/Female groups detected")
        else:
            score += 4
            feedback.append("T-Test: Gender found but Male/Female groups not confirmed")
    else:
        feedback.append("T-Test: grouping variable Gender not found")

    # Check for t-test specific output (t-statistic, p-value, df)
    ttest_output_keywords = ["statistic", "p-value", "p value", "df",
                             "degrees of freedom", "cohen", "effect size"]
    ttest_output_found = sum(1 for kw in ttest_output_keywords if kw in html_lower)
    if ttest_output_found >= 2:
        score += 3
        feedback.append(f"T-Test: {ttest_output_found} output statistics detected")
    elif ttest_output_found >= 1:
        score += 1
        feedback.append(f"T-Test: {ttest_output_found} output statistic detected (expected 2+)")
    else:
        feedback.append("T-Test: no t-test output statistics detected")

    return score, feedback


def _check_correlation_in_html(html_content):
    """
    Check if Correlation Matrix is present with correct variables.
    Returns (score, feedback_parts) where score is 0-25.
    """
    score = 0
    feedback = []
    html_lower = html_content.lower()

    # Check for Correlation analysis presence
    corr_patterns = [
        "correlation matrix",
        "correlation-matrix",
        "correlationmatrix",
        "jmv-corrmatrix",
        "corrmatrix",
    ]
    has_correlation = any(pat in html_lower for pat in corr_patterns)

    if not has_correlation:
        # Looser check: "correlation" or "pearson" may appear
        if "correlation" in html_lower or "pearson" in html_lower:
            score += 3
            feedback.append(
                "Correlation: correlation/Pearson reference found but Correlation Matrix not confirmed"
            )
        else:
            feedback.append("Correlation: analysis NOT found in output")
        return score, feedback

    score += 8
    feedback.append("Correlation: Correlation Matrix found in output")

    # Check that all three variables appear
    found_vars = set()
    for var in EXPECTED_ANALYSIS_VARS:
        if var.lower() in html_lower:
            found_vars.add(var)

    if len(found_vars) >= 3:
        score += 8
        feedback.append(f"Correlation: all 3 variables found ({', '.join(sorted(found_vars))})")
    elif len(found_vars) >= 2:
        score += 4
        feedback.append(
            f"Correlation: {len(found_vars)}/3 variables found ({', '.join(sorted(found_vars))})"
        )
    else:
        feedback.append(f"Correlation: only {len(found_vars)}/3 expected variables found")

    # Check for Pearson correlation specifics
    if "pearson" in html_lower:
        score += 5
        feedback.append("Correlation: Pearson correlation type confirmed")
    else:
        # Jamovi defaults to Pearson so it may not be explicitly labeled
        score += 2
        feedback.append("Correlation: Pearson not explicitly confirmed (may be default)")

    # Check for correlation output (p-values, r values, significance markers)
    corr_output_keywords = ["p-value", "p value", "significance", "***", "**", "*",
                            "spearman", "pearson's r"]
    corr_output_found = sum(1 for kw in corr_output_keywords if kw in html_lower)
    if corr_output_found >= 2:
        score += 4
        feedback.append(f"Correlation: {corr_output_found} output elements detected")
    elif corr_output_found >= 1:
        score += 2
        feedback.append(f"Correlation: {corr_output_found} output element detected")
    else:
        feedback.append("Correlation: no correlation output elements detected")

    return score, feedback


def verify_exam_multi_analysis(traj, env_info, task_info):
    """
    Verify the exam_multi_analysis task.

    Criteria:
      1. (15 pts) File saved at correct path
      2. (10 pts) File is a valid .omv (ZIP with expected structure)
      3. (25 pts) Descriptives with Exam/Revise/Anxiety split by Gender
      4. (25 pts) Independent Samples T-Test with Exam as DV, Gender as grouping var
      5. (25 pts) Correlation Matrix with Exam, Revise, Anxiety

    Pass threshold: 70/100
    """
    copy_from_env = env_info.get("copy_from_env")
    score = 0
    feedback_parts = []
    temp_dir = None

    # ==================================================================
    # Output-existence gate: if no .omv file exists, return score=0
    # ==================================================================
    try:
        temp_dir, extract_dir, file_size = _extract_omv_file(
            OMV_OUTPUT_FILE, copy_from_env
        )
    except FileNotFoundError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found or could not be extracted: {e}",
        }
    except zipfile.BadZipFile:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file exists but is not a valid ZIP/.omv archive",
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error accessing output file: {e}",
        }

    try:
        # ==============================================================
        # Criterion 1 (15 pts): File saved at correct path
        # ==============================================================
        try:
            c1_score = 15
            feedback_parts.append(f"File exists: {OMV_OUTPUT_FILE} ({file_size} bytes)")
            score += c1_score
            logger.info(f"Criterion 1 (File exists): {c1_score}/15")
        except Exception as e:
            logger.error(f"Criterion 1 error: {e}", exc_info=True)
            feedback_parts.append(f"File exists: verification error ({e})")

        # ==============================================================
        # Criterion 2 (10 pts): Valid .omv structure
        # ==============================================================
        try:
            c2_score = 0

            # Check file size is reasonable (an .omv with data + analyses should be > 1KB)
            if file_size >= 1000:
                c2_score += 3
                feedback_parts.append(f"File size: {file_size} bytes (reasonable)")
            elif file_size > 0:
                c2_score += 1
                feedback_parts.append(f"File size: {file_size} bytes (small)")
            else:
                feedback_parts.append("File size: 0 bytes (empty)")

            # Check for expected .omv contents
            has_index = False
            has_meta = False
            has_data = False
            all_files = []
            for root, dirs, files in os.walk(extract_dir):
                for f in files:
                    rel = os.path.relpath(os.path.join(root, f), extract_dir)
                    all_files.append(rel)
                    if f == "index.html":
                        has_index = True
                    if f in ("META-INF", "MANIFEST.MF", "metadata.json", "xdata.json"):
                        has_meta = True
                    if f.endswith(".csv") or f in ("data.bin", "strings.bin", "xdata.json"):
                        has_data = True

            # Also check for META-INF directory
            meta_inf_dir = os.path.join(extract_dir, "META-INF")
            if os.path.isdir(meta_inf_dir):
                has_meta = True

            if has_index:
                c2_score += 4
                feedback_parts.append("Structure: index.html found")
            else:
                feedback_parts.append("Structure: index.html NOT found")

            if has_meta or has_data:
                c2_score += 3
                feedback_parts.append(
                    f"Structure: metadata/data files present ({len(all_files)} total files)"
                )
            else:
                feedback_parts.append("Structure: no metadata/data files found")

            score += c2_score
            logger.info(f"Criterion 2 (Valid structure): {c2_score}/10")

        except Exception as e:
            logger.error(f"Criterion 2 error: {e}", exc_info=True)
            feedback_parts.append(f"Valid structure: verification error ({e})")

        # ==============================================================
        # Read index.html for analysis verification
        # ==============================================================
        html_content = _read_index_html(extract_dir)

        if html_content is None:
            # No index.html -- try to use export_result.sh output as fallback
            result_data = _read_result_json()
            feedback_parts.append("index.html not found; using export_result.sh data as fallback")

            # Award partial credit based on export_result.sh findings
            if result_data.get("has_descriptives"):
                score += 10
                feedback_parts.append("Descriptives: detected by export script (partial credit)")
            else:
                feedback_parts.append("Descriptives: not detected by export script")

            if result_data.get("has_ttest"):
                score += 10
                feedback_parts.append("T-Test: detected by export script (partial credit)")
            else:
                feedback_parts.append("T-Test: not detected by export script")

            if result_data.get("has_correlation"):
                score += 10
                feedback_parts.append("Correlation: detected by export script (partial credit)")
            else:
                feedback_parts.append("Correlation: not detected by export script")

        else:
            # ==============================================================
            # Criterion 3 (25 pts): Descriptives analysis
            # ==============================================================
            try:
                c3_score, c3_feedback = _check_descriptives_in_html(html_content)
                score += c3_score
                feedback_parts.extend(c3_feedback)
                logger.info(f"Criterion 3 (Descriptives): {c3_score}/25")
            except Exception as e:
                logger.error(f"Criterion 3 error: {e}", exc_info=True)
                feedback_parts.append(f"Descriptives: verification error ({e})")

            # ==============================================================
            # Criterion 4 (25 pts): Independent Samples T-Test
            # ==============================================================
            try:
                c4_score, c4_feedback = _check_ttest_in_html(html_content)
                score += c4_score
                feedback_parts.extend(c4_feedback)
                logger.info(f"Criterion 4 (T-Test): {c4_score}/25")
            except Exception as e:
                logger.error(f"Criterion 4 error: {e}", exc_info=True)
                feedback_parts.append(f"T-Test: verification error ({e})")

            # ==============================================================
            # Criterion 5 (25 pts): Correlation Matrix
            # ==============================================================
            try:
                c5_score, c5_feedback = _check_correlation_in_html(html_content)
                score += c5_score
                feedback_parts.extend(c5_feedback)
                logger.info(f"Criterion 5 (Correlation): {c5_score}/25")
            except Exception as e:
                logger.error(f"Criterion 5 error: {e}", exc_info=True)
                feedback_parts.append(f"Correlation: verification error ({e})")

        # ==============================================================
        # Final result
        # ==============================================================
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

    except Exception as e:
        logger.error(f"Top-level verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {e}",
        }

    finally:
        # Clean up temp directory
        if temp_dir and os.path.isdir(temp_dir):
            try:
                import shutil
                shutil.rmtree(temp_dir, ignore_errors=True)
            except Exception:
                pass
