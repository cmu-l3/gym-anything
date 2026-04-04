#!/usr/bin/env python3
"""
Verifier for paired_samples_analysis task.

Copies the saved .jasp file from the VM, unzips it, and parses
analyses.json to verify the agent correctly configured:
  1. A paired samples t-test with correct variable pairing
  2. Effect size (Cohen's d) enabled
  3. Descriptive statistics analysis with correct variables
  4. Substantial file with computed results
  5. Actual computed t-statistic and p-value in results
"""

import json
import logging
import os
import tempfile
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_paired_samples_analysis(traj, env_info, task_info):
    """
    Verify that paired samples t-test and descriptive statistics
    were correctly configured and computed in the saved .jasp file.

    Scoring (100 points total):
      - Criterion 1 (25 pts): Paired t-test exists with correct variable pairing
      - Criterion 2 (20 pts): Effect size (Cohen's d) is enabled
      - Criterion 3 (25 pts): Descriptive statistics analysis with correct variables
      - Criterion 4 (15 pts): File is substantial (>5KB, has computed results)
      - Criterion 5 (15 pts): Results contain actual computed t-statistic and p-value
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in env_info"
        }

    vm_path = "/home/ga/Documents/JASP/weight_gain_analysis.jasp"
    temp_dir = tempfile.mkdtemp(prefix="jasp_verify_paired_")
    local_jasp = os.path.join(temp_dir, "weight_gain_analysis.jasp")

    score = 0
    feedback_parts = []

    try:
        # ------------------------------------------------------------------
        # Gate check: copy the .jasp file from the VM
        # ------------------------------------------------------------------
        try:
            copy_from_env(vm_path, local_jasp)
        except Exception as e:
            logger.error(f"Failed to copy .jasp file from VM: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Output file not found or could not be copied from VM: {e}"
            }

        if not os.path.exists(local_jasp):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Output .jasp file does not exist at "
                            "/home/ga/Documents/JASP/weight_gain_analysis.jasp"
            }

        file_size = os.path.getsize(local_jasp)
        if file_size < 100:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Output .jasp file is too small ({file_size} bytes) "
                            "- likely empty or corrupt"
            }

        # ------------------------------------------------------------------
        # Unzip the .jasp file (it is a ZIP archive)
        # ------------------------------------------------------------------
        extract_dir = os.path.join(temp_dir, "extracted")
        try:
            with zipfile.ZipFile(local_jasp, 'r') as zf:
                zf.extractall(extract_dir)
        except zipfile.BadZipFile:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Output .jasp file is not a valid ZIP archive"
            }

        # ------------------------------------------------------------------
        # Parse analyses.json
        # ------------------------------------------------------------------
        analyses_path = os.path.join(extract_dir, "analyses.json")
        if not os.path.exists(analyses_path):
            return {
                "passed": False,
                "score": 0,
                "feedback": "analyses.json not found inside .jasp archive"
            }

        with open(analyses_path, 'r') as f:
            analyses_data = json.load(f)

        # analyses.json may be a list or a dict with an "analyses" key
        if isinstance(analyses_data, list):
            analyses = analyses_data
        elif isinstance(analyses_data, dict):
            analyses = analyses_data.get("analyses", [])
        else:
            analyses = []

        if not analyses:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No analyses found in analyses.json"
            }

        # ------------------------------------------------------------------
        # WRONG-TARGET GATE: Must have a paired t-test with correct variables
        # ------------------------------------------------------------------
        paired_ttest_found = False
        paired_vars_correct = False
        ttest_analysis = None

        expected_vars = {"Weight Before", "Weight After"}

        for analysis in analyses:
            name = analysis.get("name", "").lower()
            module = analysis.get("module", "").lower()
            analysis_type = analysis.get("analysisType", "").lower() if "analysisType" in analysis else ""

            is_ttest = any(kw in name for kw in [
                "ttest", "t-test", "pairedsamples", "paired"
            ]) or any(kw in module for kw in [
                "ttest", "t-test", "ttestpairedsamples"
            ]) or any(kw in analysis_type for kw in [
                "ttest", "paired"
            ])

            if not is_ttest:
                continue

            paired_ttest_found = True
            ttest_analysis = analysis
            opts = analysis.get("options", {})

            pairs = opts.get("pairs", [])
            if pairs:
                for pair in pairs:
                    if isinstance(pair, list) and len(pair) >= 2:
                        pair_set = set(pair[:2])
                        if expected_vars.issubset(pair_set) or pair_set == expected_vars:
                            paired_vars_correct = True
                            break
                    elif isinstance(pair, dict):
                        p1 = pair.get("variable1", pair.get("lhs", ""))
                        p2 = pair.get("variable2", pair.get("rhs", ""))
                        if {p1, p2} == expected_vars:
                            paired_vars_correct = True
                            break

            if paired_ttest_found:
                break

        if not paired_ttest_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Wrong target: No paired samples t-test analysis "
                            "found in analyses.json"
            }

        if not paired_vars_correct:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Wrong target: Paired t-test found but does not use "
                            "the required variables (Weight Before, Weight After)"
            }

        # ------------------------------------------------------------------
        # Criterion 1 (25 pts): Paired t-test with correct variable pairing
        # ------------------------------------------------------------------
        score += 25
        feedback_parts.append(
            "Criterion 1 PASSED (25/25): Paired t-test found with "
            "correct variable pairing (Weight Before vs Weight After)"
        )

        # ------------------------------------------------------------------
        # Criterion 2 (20 pts): Effect size (Cohen's d) enabled
        # ------------------------------------------------------------------
        try:
            effect_size_enabled = False

            if ttest_analysis:
                opts = ttest_analysis.get("options", {})

                # JASP uses "effectSize" boolean for Cohen's d in paired t-test
                if opts.get("effectSize", False):
                    effect_size_enabled = True
                # Alternative key names in different JASP versions
                elif opts.get("effectSizeCohenD", False):
                    effect_size_enabled = True
                elif opts.get("cohensd", False):
                    effect_size_enabled = True
                # Check effectSizeType if present
                elif "effectSizeType" in opts:
                    es_type = opts["effectSizeType"]
                    if isinstance(es_type, str) and "cohen" in es_type.lower():
                        effect_size_enabled = True
                    elif isinstance(es_type, list) and any(
                        "cohen" in str(t).lower() for t in es_type
                    ):
                        effect_size_enabled = True
                # Sometimes stored under "options" -> "effectSize" as True
                # or as a sub-dict
                elif isinstance(opts.get("effectSize"), dict):
                    if opts["effectSize"].get("cohensD", False):
                        effect_size_enabled = True

            if effect_size_enabled:
                score += 20
                feedback_parts.append(
                    "Criterion 2 PASSED (20/20): Effect size (Cohen's d) "
                    "is enabled in the paired t-test"
                )
            else:
                feedback_parts.append(
                    "Criterion 2 FAILED (0/20): Effect size (Cohen's d) "
                    "not detected as enabled in the t-test options"
                )
        except Exception as e:
            logger.error(f"Criterion 2 error: {e}", exc_info=True)
            feedback_parts.append(
                f"Criterion 2 ERROR (0/20): {e}"
            )

        # ------------------------------------------------------------------
        # Criterion 3 (25 pts): Descriptive statistics analysis with
        #                        correct variables
        # ------------------------------------------------------------------
        try:
            descriptives_found = False
            descriptives_vars_correct = False

            expected_desc_vars = {"Weight Before", "Weight After", "Difference"}

            for analysis in analyses:
                name = analysis.get("name", "").lower()
                module = analysis.get("module", "").lower()

                is_descriptives = any(kw in name for kw in [
                    "descriptive", "descriptives"
                ]) or any(kw in module for kw in [
                    "descriptive", "descriptives", "jaspdescriptives"
                ])

                # Exclude the t-test's built-in descriptives option
                # (we want a separate Descriptives analysis)
                if is_descriptives and not any(kw in name for kw in [
                    "ttest", "t-test", "paired"
                ]):
                    descriptives_found = True
                    opts = analysis.get("options", {})

                    # JASP stores descriptives variables in "variables" key
                    desc_vars = opts.get("variables", [])
                    if isinstance(desc_vars, list):
                        desc_var_set = set(desc_vars)
                        if expected_desc_vars.issubset(desc_var_set):
                            descriptives_vars_correct = True
                        elif len(desc_var_set & expected_desc_vars) >= 2:
                            # At least 2 of 3 variables present
                            descriptives_vars_correct = True

                    if descriptives_found:
                        break

            if descriptives_found and descriptives_vars_correct:
                score += 25
                feedback_parts.append(
                    "Criterion 3 PASSED (25/25): Descriptive statistics "
                    "analysis found with correct variables"
                )
            elif descriptives_found:
                score += 10
                feedback_parts.append(
                    "Criterion 3 PARTIAL (10/25): Descriptive statistics "
                    "analysis found but variable selection incomplete"
                )
            else:
                feedback_parts.append(
                    "Criterion 3 FAILED (0/25): No separate descriptive "
                    "statistics analysis found in analyses.json"
                )
        except Exception as e:
            logger.error(f"Criterion 3 error: {e}", exc_info=True)
            feedback_parts.append(
                f"Criterion 3 ERROR (0/25): {e}"
            )

        # ------------------------------------------------------------------
        # Criterion 4 (15 pts): File is substantial with computed results
        # ------------------------------------------------------------------
        try:
            has_results_files = False
            results_dir = os.path.join(extract_dir, "resources")

            if os.path.isdir(results_dir):
                for root, dirs, files in os.walk(results_dir):
                    for fname in files:
                        if fname == "jaspResults.json":
                            fpath = os.path.join(root, fname)
                            fsize = os.path.getsize(fpath)
                            if fsize > 100:
                                has_results_files = True
                                break
                    if has_results_files:
                        break

            if file_size > 5000 and has_results_files:
                score += 15
                feedback_parts.append(
                    f"Criterion 4 PASSED (15/15): File is substantial "
                    f"({file_size} bytes) with computed results"
                )
            elif file_size > 5000:
                score += 8
                feedback_parts.append(
                    f"Criterion 4 PARTIAL (8/15): File is substantial "
                    f"({file_size} bytes) but jaspResults.json not found"
                )
            elif has_results_files:
                score += 8
                feedback_parts.append(
                    f"Criterion 4 PARTIAL (8/15): Has computed results "
                    f"but file is small ({file_size} bytes)"
                )
            else:
                feedback_parts.append(
                    f"Criterion 4 FAILED (0/15): File is too small "
                    f"({file_size} bytes) and no computed results found"
                )
        except Exception as e:
            logger.error(f"Criterion 4 error: {e}", exc_info=True)
            feedback_parts.append(
                f"Criterion 4 ERROR (0/15): {e}"
            )

        # ------------------------------------------------------------------
        # Criterion 5 (15 pts): Results contain computed t-statistic
        #                        and p-value
        # ------------------------------------------------------------------
        try:
            found_t_stat = False
            found_p_value = False
            t_value = None
            p_value = None

            results_dir = os.path.join(extract_dir, "resources")
            if os.path.isdir(results_dir):
                for root, dirs, files in os.walk(results_dir):
                    for fname in files:
                        if fname != "jaspResults.json":
                            continue
                        fpath = os.path.join(root, fname)
                        try:
                            with open(fpath, 'r') as f:
                                rdata = json.load(f)
                            # Search recursively for t-statistic and p-value
                            results_str = json.dumps(rdata)
                            if _search_for_key(rdata, "t", numeric=True) is not None:
                                found_t_stat = True
                                t_value = _search_for_key(rdata, "t", numeric=True)
                            if _search_for_key(rdata, "statistic", numeric=True) is not None:
                                found_t_stat = True
                                if t_value is None:
                                    t_value = _search_for_key(rdata, "statistic", numeric=True)
                            if _search_for_key(rdata, "p", numeric=True) is not None:
                                found_p_value = True
                                p_value = _search_for_key(rdata, "p", numeric=True)
                            if _search_for_key(rdata, "pValue", numeric=True) is not None:
                                found_p_value = True
                                if p_value is None:
                                    p_value = _search_for_key(rdata, "pValue", numeric=True)
                        except Exception:
                            pass

            if found_t_stat and found_p_value:
                score += 15
                detail = ""
                if t_value is not None:
                    detail += f" t={t_value:.4f}"
                if p_value is not None:
                    detail += f" p={p_value:.4f}"
                feedback_parts.append(
                    f"Criterion 5 PASSED (15/15): Computed results contain "
                    f"t-statistic and p-value{detail}"
                )
            elif found_t_stat or found_p_value:
                score += 8
                feedback_parts.append(
                    "Criterion 5 PARTIAL (8/15): Found "
                    f"{'t-statistic' if found_t_stat else 'p-value'} "
                    "but not both"
                )
            else:
                feedback_parts.append(
                    "Criterion 5 FAILED (0/15): No computed t-statistic "
                    "or p-value found in jaspResults.json"
                )
        except Exception as e:
            logger.error(f"Criterion 5 error: {e}", exc_info=True)
            feedback_parts.append(
                f"Criterion 5 ERROR (0/15): {e}"
            )

        # ------------------------------------------------------------------
        # Final result
        # ------------------------------------------------------------------
        passed = score >= 70
        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Unexpected verification error: {e}"
        }
    finally:
        # Clean up temp directory
        try:
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
        except Exception:
            pass


def _search_for_key(obj, target_key, numeric=False, depth=0):
    """
    Recursively search a nested JSON structure for a key and return
    the first matching value. Limits recursion depth to avoid
    infinite loops.

    Args:
        obj: The JSON object to search (dict, list, or primitive)
        target_key: The key name to search for
        numeric: If True, only return values that are numeric (int/float)
        depth: Current recursion depth (internal use)

    Returns:
        The first matching value found, or None if not found.
    """
    if depth > 20:
        return None

    if isinstance(obj, dict):
        for key, value in obj.items():
            if key == target_key:
                if numeric:
                    if isinstance(value, (int, float)) and not isinstance(value, bool):
                        return value
                else:
                    return value
            # Recurse into nested structures
            result = _search_for_key(value, target_key, numeric, depth + 1)
            if result is not None:
                return result
    elif isinstance(obj, list):
        for item in obj:
            result = _search_for_key(item, target_key, numeric, depth + 1)
            if result is not None:
                return result

    return None
