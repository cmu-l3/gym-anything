#!/usr/bin/env python3
"""
Verifier for regression_model_comparison task.

Copies the saved .jasp file from the VM, unzips it, and parses
analyses.json to verify that the agent correctly configured a
multiple linear regression with appropriate diagnostics.

Scoring (100 points total, pass threshold 70):
  Criterion 1 (25 pts): Linear regression analysis with correct DV
  Criterion 2 (25 pts): All 4 required covariates included
  Criterion 3 (20 pts): Residual diagnostic plots enabled
  Criterion 4 (15 pts): Collinearity diagnostics (VIF) enabled
  Criterion 5 (15 pts): File substantial with computed results
"""

import json
import os
import logging
import tempfile
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

JASP_FILE_VM_PATH = "/home/ga/Documents/JASP/happiness_regression.jasp"
EXPECTED_DV = "Happiness Score"
EXPECTED_COVARIATES = {"GDP per Capita", "Family", "Life Expectancy", "Freedom"}
PASS_THRESHOLD = 70


def _normalize_var_name(name):
    """Normalize a variable name for fuzzy matching."""
    if not name:
        return ""
    return name.strip().lower().replace("_", " ").replace("-", " ")


def _find_regression_analyses(analyses):
    """Find linear regression analyses from the analyses list."""
    regression_analyses = []
    for a in analyses:
        analysis_name = (a.get("analysis", "") or "").lower()
        module_name = (a.get("module", "") or "").lower()
        name_field = (a.get("name", "") or "").lower()

        is_regression = (
            "regression" in analysis_name
            or "regression" in module_name
            or "regression" in name_field
        )
        is_correlation = (
            "correlation" in analysis_name
            or "correlation" in name_field
        )

        if is_regression and not is_correlation:
            regression_analyses.append(a)

    return regression_analyses


def _check_dv(options, expected_dv):
    """Check whether the dependent variable matches expected DV."""
    expected_norm = _normalize_var_name(expected_dv)

    for key in ["dependent", "dependentVariable", "dependentVariables", "outcome"]:
        val = options.get(key)
        if val is None:
            continue
        if isinstance(val, str):
            if _normalize_var_name(val) == expected_norm:
                return True
        elif isinstance(val, list):
            for v in val:
                if isinstance(v, str) and _normalize_var_name(v) == expected_norm:
                    return True
        elif isinstance(val, dict):
            inner = val.get("value", val.get("name", ""))
            if isinstance(inner, str) and _normalize_var_name(inner) == expected_norm:
                return True

    return False


def _check_covariates(options, expected_covariates):
    """Check which expected covariates are present. Returns (found, missing)."""
    expected_norm = {_normalize_var_name(c) for c in expected_covariates}
    found_norm = set()

    for key in ["covariates", "independentVariables"]:
        val = options.get(key)
        if val is None:
            continue
        if isinstance(val, list):
            for item in val:
                if isinstance(item, str):
                    norm = _normalize_var_name(item)
                    if norm in expected_norm:
                        found_norm.add(norm)
                elif isinstance(item, dict):
                    for sub_key in ["value", "name", "variable"]:
                        if sub_key in item:
                            norm = _normalize_var_name(str(item[sub_key]))
                            if norm in expected_norm:
                                found_norm.add(norm)

    model_terms = options.get("modelTerms", [])
    if isinstance(model_terms, list):
        for term in model_terms:
            if isinstance(term, dict):
                components = term.get("components", [])
                if isinstance(components, list):
                    for comp in components:
                        if isinstance(comp, str):
                            norm = _normalize_var_name(comp)
                            if norm in expected_norm:
                                found_norm.add(norm)
            elif isinstance(term, str):
                norm = _normalize_var_name(term)
                if norm in expected_norm:
                    found_norm.add(norm)

    norm_to_original = {_normalize_var_name(c): c for c in expected_covariates}
    found_original = {norm_to_original[n] for n in found_norm if n in norm_to_original}
    missing_original = expected_covariates - found_original
    return found_original, missing_original


def _check_residual_plots(options):
    """Check if residual diagnostic plots are enabled. Returns (qq, vs_fitted)."""
    plot_keys_qq = [
        "residualQqPlot", "residualVsQqPlot", "plotQQresidual",
        "qqPlot", "plotResidualQq", "residualsQQ",
        "plotsResidualQQ", "residualStatisticsQqPlot",
    ]
    plot_keys_vs_fitted = [
        "residualVsFittedPlot", "plotResidualsVsFitted",
        "residualVsPredictedPlot", "plotResidualVsFitted",
        "plotsResidualFitted", "residualVsDependentPlot",
        "residualStatisticsFittedPlot",
    ]

    qq_enabled = False
    vs_fitted_enabled = False

    for key in plot_keys_qq:
        if options.get(key) is True:
            qq_enabled = True
            break
    for key in plot_keys_vs_fitted:
        if options.get(key) is True:
            vs_fitted_enabled = True
            break

    for parent_key in ["plotsResidualsAgainst", "residualPlots", "diagnosticPlots", "plots"]:
        nested = options.get(parent_key)
        if isinstance(nested, dict):
            for key in plot_keys_qq:
                if nested.get(key) is True:
                    qq_enabled = True
            for key in plot_keys_vs_fitted:
                if nested.get(key) is True:
                    vs_fitted_enabled = True
        elif nested is True:
            qq_enabled = True
            vs_fitted_enabled = True

    for key, val in options.items():
        key_lower = key.lower()
        if val is True:
            if "residual" in key_lower and "qq" in key_lower:
                qq_enabled = True
            if "residual" in key_lower and ("fitted" in key_lower or "predicted" in key_lower):
                vs_fitted_enabled = True

    return qq_enabled, vs_fitted_enabled


def _check_collinearity(options):
    """Check if collinearity diagnostics (VIF) are enabled."""
    collinearity_keys = [
        "collinearityDiagnostic", "collinearityDiagnostics",
        "collinearityStatistic", "collinearityStatistics",
        "vif", "VIF", "multicollinearity", "collinearity",
    ]

    for key in collinearity_keys:
        if options.get(key) is True:
            return True

    for parent_key in ["statistics", "diagnostics"]:
        nested = options.get(parent_key)
        if isinstance(nested, dict):
            for key in collinearity_keys:
                if nested.get(key) is True:
                    return True

    for key, val in options.items():
        key_lower = key.lower()
        if val is True and ("collinear" in key_lower or key_lower in ("vif",)):
            return True

    return False


def verify_regression_model_comparison(traj, env_info, task_info):
    """
    Verify the regression model comparison task by copying the .jasp file
    from the VM, unzipping it, and parsing analyses.json.

    Returns a dict with 'passed', 'score', and 'feedback'.
    Pass threshold: 70/100.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in env_info"
        }

    temp_dir = tempfile.mkdtemp(prefix="jasp_verify_regression_")
    local_jasp = os.path.join(temp_dir, "happiness_regression.jasp")

    score = 0
    feedback_parts = []

    try:
        # ==============================================================
        # Gate: copy .jasp file from VM
        # ==============================================================
        try:
            copy_from_env(JASP_FILE_VM_PATH, local_jasp)
        except Exception as e:
            logger.error("Failed to copy .jasp file from VM: %s", e)
            return {
                "passed": False,
                "score": 0,
                "feedback": "Output file not found or could not be copied: {}".format(e)
            }

        if not os.path.exists(local_jasp):
            return {"passed": False, "score": 0,
                    "feedback": "Output .jasp file not found at " + JASP_FILE_VM_PATH}

        file_size = os.path.getsize(local_jasp)
        if file_size < 100:
            return {"passed": False, "score": 0,
                    "feedback": "Output .jasp file too small ({} bytes)".format(file_size)}

        # ==============================================================
        # Unzip the .jasp file
        # ==============================================================
        extract_dir = os.path.join(temp_dir, "extracted")
        try:
            with zipfile.ZipFile(local_jasp, 'r') as zf:
                zf.extractall(extract_dir)
        except zipfile.BadZipFile:
            return {"passed": False, "score": 0,
                    "feedback": "Output .jasp file is not a valid ZIP archive"}

        # ==============================================================
        # Parse analyses.json
        # ==============================================================
        analyses_path = os.path.join(extract_dir, "analyses.json")
        if not os.path.exists(analyses_path):
            return {"passed": False, "score": 0,
                    "feedback": "analyses.json not found inside .jasp archive"}

        with open(analyses_path, 'r') as f:
            analyses_data = json.load(f)

        if isinstance(analyses_data, list):
            analyses = analyses_data
        elif isinstance(analyses_data, dict):
            analyses = analyses_data.get("analyses", [])
        else:
            analyses = []

        if not analyses:
            return {"passed": False, "score": 0,
                    "feedback": "No analyses found in analyses.json"}

        # Find regression analyses
        regression_analyses = _find_regression_analyses(analyses)

        # ==============================================================
        # WRONG-TARGET GATE: Regression must exist with correct DV
        # ==============================================================
        if not regression_analyses:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Wrong target: No linear regression analysis found. "
                            "Found: {}".format([a.get("name", "unknown") for a in analyses])
            }

        dv_correct = False
        for ra in regression_analyses:
            if _check_dv(ra.get("options", {}), EXPECTED_DV):
                dv_correct = True
                break

        if not dv_correct:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Wrong target: Regression found but dependent variable is not "
                            "'{}'. Analysis is fundamentally wrong.".format(EXPECTED_DV)
            }

        # ==============================================================
        # Criterion 1 (25 pts): Regression with correct DV
        # ==============================================================
        score += 25
        feedback_parts.append(
            "Criterion 1 (25/25): Linear regression with correct DV '{}'".format(EXPECTED_DV))

        # ==============================================================
        # Criterion 2 (25 pts): All 4 covariates included
        # ==============================================================
        try:
            best_found = set()
            best_missing = EXPECTED_COVARIATES.copy()

            for ra in regression_analyses:
                found, missing = _check_covariates(ra.get("options", {}), EXPECTED_COVARIATES)
                if len(found) > len(best_found):
                    best_found = found
                    best_missing = missing

            n = len(best_found)
            if n == 4:
                score += 25
                feedback_parts.append("Criterion 2 (25/25): All 4 covariates included")
            elif n >= 3:
                score += 18
                feedback_parts.append("Criterion 2 (18/25): {}/4 covariates. Missing: {}".format(
                    n, sorted(best_missing)))
            elif n >= 2:
                score += 12
                feedback_parts.append("Criterion 2 (12/25): {}/4 covariates. Missing: {}".format(
                    n, sorted(best_missing)))
            elif n >= 1:
                score += 6
                feedback_parts.append("Criterion 2 (6/25): {}/4 covariates".format(n))
            else:
                feedback_parts.append("Criterion 2 (0/25): No expected covariates found")
        except Exception as e:
            feedback_parts.append("Criterion 2 (0/25): Error: {}".format(e))

        # ==============================================================
        # Criterion 3 (20 pts): Residual diagnostic plots
        # ==============================================================
        try:
            qq_found = False
            vs_fitted_found = False
            for ra in regression_analyses:
                qq, vs_fitted = _check_residual_plots(ra.get("options", {}))
                if qq:
                    qq_found = True
                if vs_fitted:
                    vs_fitted_found = True

            if qq_found and vs_fitted_found:
                score += 20
                feedback_parts.append("Criterion 3 (20/20): Both Q-Q and residuals-vs-predicted plots enabled")
            elif qq_found or vs_fitted_found:
                score += 12
                feedback_parts.append("Criterion 3 (12/20): One residual plot type enabled")
            else:
                feedback_parts.append("Criterion 3 (0/20): No residual diagnostic plots enabled")
        except Exception as e:
            feedback_parts.append("Criterion 3 (0/20): Error: {}".format(e))

        # ==============================================================
        # Criterion 4 (15 pts): Collinearity diagnostics (VIF)
        # ==============================================================
        try:
            vif_found = False
            for ra in regression_analyses:
                if _check_collinearity(ra.get("options", {})):
                    vif_found = True
                    break

            if vif_found:
                score += 15
                feedback_parts.append("Criterion 4 (15/15): Collinearity diagnostics (VIF) enabled")
            else:
                feedback_parts.append("Criterion 4 (0/15): VIF not enabled")
        except Exception as e:
            feedback_parts.append("Criterion 4 (0/15): Error: {}".format(e))

        # ==============================================================
        # Criterion 5 (15 pts): File substantial with computed results
        # ==============================================================
        try:
            has_results = False
            results_dir = os.path.join(extract_dir, "resources")
            result_count = 0

            if os.path.isdir(results_dir):
                for root, dirs, files in os.walk(results_dir):
                    for fname in files:
                        if fname == "jaspResults.json":
                            fpath = os.path.join(root, fname)
                            if os.path.getsize(fpath) > 100:
                                has_results = True
                                result_count += 1

            if file_size > 10000 and has_results:
                score += 15
                feedback_parts.append(
                    "Criterion 5 (15/15): File substantial ({} bytes, {} result files)".format(
                        file_size, result_count))
            elif file_size > 10000:
                score += 10
                feedback_parts.append(
                    "Criterion 5 (10/15): File substantial ({} bytes) but no results found".format(file_size))
            elif has_results:
                score += 8
                feedback_parts.append(
                    "Criterion 5 (8/15): Results present but file small ({} bytes)".format(file_size))
            else:
                feedback_parts.append(
                    "Criterion 5 (0/15): File too small ({} bytes), no results".format(file_size))
        except Exception as e:
            feedback_parts.append("Criterion 5 (0/15): Error: {}".format(e))

        # ==============================================================
        # Final result
        # ==============================================================
        passed = score >= PASS_THRESHOLD
        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error("Verification error: %s", e, exc_info=True)
        return {"passed": False, "score": 0, "feedback": "Unexpected error: {}".format(e)}
    finally:
        try:
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
        except Exception:
            pass
