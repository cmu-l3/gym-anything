#!/usr/bin/env python3
"""
Verifier for nonparametric_group_comparison task (JASP Heart Rate dataset).

Copies the saved .jasp file from the VM, unzips it, and parses
analyses.json to verify that the agent correctly configured:
  1. Kruskal-Wallis test with Heart Rate as DV and Group as grouping var
  2. Mann-Whitney U test with Heart Rate as DV and Gender as grouping var
  3. Descriptive Statistics for Heart Rate split by Group with plots
  4. At least 3 distinct analyses configured
  5. File substantial with computed results

Scoring (100 points total, pass threshold 70):
  Criterion 1 (25 pts): Kruskal-Wallis analysis with correct DV and grouping var
  Criterion 2 (25 pts): Mann-Whitney U analysis with correct DV and grouping var
  Criterion 3 (20 pts): Descriptives with Heart Rate split by Group + plots
  Criterion 4 (15 pts): At least 3 distinct analyses configured
  Criterion 5 (15 pts): File substantial with computed results
"""

import json
import logging
import os
import tempfile
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

JASP_FILE_VM_PATH = "/home/ga/Documents/JASP/heart_rate_nonparametric.jasp"
PASS_THRESHOLD = 70


def _normalize(s):
    """Normalize a string for fuzzy matching: lowercase, strip spaces/underscores."""
    if not isinstance(s, str):
        return ""
    return s.lower().replace(" ", "").replace("_", "").replace("-", "")


def _options_contain_var(opts, var_name, field_names):
    """Check whether any of *field_names* in the options dict references *var_name*."""
    if not isinstance(opts, dict):
        return False
    norm_var = _normalize(var_name)
    for field in field_names:
        val = opts.get(field)
        if val is None:
            continue
        if isinstance(val, str):
            if _normalize(val) == norm_var:
                return True
        elif isinstance(val, list):
            for item in val:
                if isinstance(item, str) and _normalize(item) == norm_var:
                    return True
                if isinstance(item, dict):
                    for v in item.values():
                        if isinstance(v, str) and _normalize(v) == norm_var:
                            return True
    return False


def _options_json_contains(opts, needle):
    """Check whether the full serialized options contain a substring (case-insensitive)."""
    try:
        return needle.lower() in json.dumps(opts).lower()
    except Exception:
        return False


def _check_plots_enabled(opts):
    """Return True if the options dict suggests plot/visualization options are on."""
    if not isinstance(opts, dict):
        return False
    opts_str = json.dumps(opts).lower()
    plot_keywords = [
        "boxplot", "distributionplot", "densityplot", "histogram",
        "plotvariables", "splitplot", "violinplot", "raincloudplot",
    ]
    for kw in plot_keywords:
        if kw in opts_str.replace(" ", "").replace("_", "").replace("-", ""):
            return True
    for key, val in opts.items():
        if "plot" in key.lower() and val is True:
            return True
    return False


def verify_nonparametric_group_comparison(traj, env_info, task_info):
    """Verify the nonparametric group comparison task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in env_info",
        }

    temp_dir = tempfile.mkdtemp(prefix="jasp_verify_nonparam_")
    local_jasp = os.path.join(temp_dir, "heart_rate_nonparametric.jasp")

    score = 0
    feedback = []

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
                "feedback": "Output file not found or could not be copied: {}".format(e),
            }

        if not os.path.exists(local_jasp):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Output .jasp file not found at " + JASP_FILE_VM_PATH,
            }

        file_size = os.path.getsize(local_jasp)
        if file_size < 100:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Output .jasp file too small ({} bytes)".format(file_size),
            }

        # ==============================================================
        # Unzip the .jasp file
        # ==============================================================
        extract_dir = os.path.join(temp_dir, "extracted")
        try:
            with zipfile.ZipFile(local_jasp, "r") as zf:
                zf.extractall(extract_dir)
        except zipfile.BadZipFile:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Output .jasp file is not a valid ZIP archive",
            }

        # ==============================================================
        # Parse analyses.json
        # ==============================================================
        analyses_path = os.path.join(extract_dir, "analyses.json")
        if not os.path.exists(analyses_path):
            return {
                "passed": False,
                "score": 0,
                "feedback": "analyses.json not found inside .jasp archive",
            }

        with open(analyses_path, "r") as f:
            analyses_data = json.load(f)

        if isinstance(analyses_data, list):
            analyses_list = analyses_data
        elif isinstance(analyses_data, dict):
            analyses_list = analyses_data.get("analyses", [])
        else:
            analyses_list = []

        if not analyses_list:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No analyses found in analyses.json",
            }

        # ==============================================================
        # WRONG-TARGET GATE: At least one analysis must reference
        # 'Heart Rate' as the DV somewhere in its options
        # ==============================================================
        any_hr_reference = False
        for analysis in analyses_list:
            opts = analysis.get("options", {})
            if _options_json_contains(opts, "heart rate"):
                any_hr_reference = True
                break

        if not any_hr_reference:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Wrong target: No analysis references 'Heart Rate' "
                            "as a variable. Analysis is fundamentally wrong.",
            }

        # ==============================================================
        # Criterion 1 (25 pts): Kruskal-Wallis with correct DV and grouping
        # ==============================================================
        try:
            kw_found = False
            kw_correct_dv = False
            kw_correct_group = False
            kw_has_descriptives = False

            for analysis in analyses_list:
                aname = _normalize(analysis.get("name", ""))
                amodule = _normalize(analysis.get("module", ""))
                opts = analysis.get("options", {})

                is_kw = any(kw in aname for kw in [
                    "kruskal", "kruskalwallis", "anovanonparametric",
                ])
                if not is_kw:
                    is_kw = any(kw in amodule for kw in ["kruskal"])
                if not is_kw:
                    is_kw = _options_json_contains(opts, "kruskal")

                if is_kw:
                    kw_found = True
                    dv_fields = [
                        "dependent", "dependentVariable", "dependentVariables",
                        "variables", "variable",
                    ]
                    if _options_contain_var(opts, "Heart Rate", dv_fields):
                        kw_correct_dv = True
                    elif _options_json_contains(opts, "heart rate"):
                        kw_correct_dv = True

                    group_fields = [
                        "fixedFactors", "groupingVariable", "factor",
                        "fixedFactor", "groupVariable", "group",
                    ]
                    if _options_contain_var(opts, "Group", group_fields):
                        kw_correct_group = True
                    elif _options_json_contains(opts, '"group"'):
                        kw_correct_group = True

                    if opts.get("descriptives") or opts.get("descriptivesTable"):
                        kw_has_descriptives = True
                    elif _options_json_contains(opts, "descriptiv"):
                        kw_has_descriptives = True

            if kw_found and kw_correct_dv and kw_correct_group:
                if kw_has_descriptives:
                    score += 25
                    feedback.append("C1 (25/25): Kruskal-Wallis with correct DV, grouping, and descriptives")
                else:
                    score += 20
                    feedback.append("C1 (20/25): Kruskal-Wallis with correct DV and grouping, no descriptives")
            elif kw_found and (kw_correct_dv or kw_correct_group):
                score += 12
                detail = "DV" if kw_correct_dv else "grouping var"
                feedback.append("C1 (12/25): Kruskal-Wallis found with correct {} only".format(detail))
            elif kw_found:
                score += 7
                feedback.append("C1 (7/25): Kruskal-Wallis found but variables not correctly assigned")
            else:
                feedback.append("C1 (0/25): No Kruskal-Wallis test found")
        except Exception as e:
            feedback.append("C1 (0/25): Error: {}".format(e))

        # ==============================================================
        # Criterion 2 (25 pts): Mann-Whitney U with correct DV and grouping
        # ==============================================================
        try:
            mw_found = False
            mw_correct_dv = False
            mw_correct_group = False
            mw_has_descriptives = False
            mw_has_effect_size = False

            for analysis in analyses_list:
                aname = _normalize(analysis.get("name", ""))
                amodule = _normalize(analysis.get("module", ""))
                opts = analysis.get("options", {})

                is_mw = any(kw in aname for kw in [
                    "mann", "whitney", "mannwhitney",
                    "ttestindependentsamplesnonparametric",
                    "ttestindsamples",
                ])
                if not is_mw:
                    is_mw = _options_json_contains(opts, "mann") or _options_json_contains(opts, "whitney")

                if is_mw:
                    mw_found = True
                    dv_fields = [
                        "dependent", "dependentVariable", "dependentVariables",
                        "variables", "variable",
                    ]
                    if _options_contain_var(opts, "Heart Rate", dv_fields):
                        mw_correct_dv = True
                    elif _options_json_contains(opts, "heart rate"):
                        mw_correct_dv = True

                    group_fields = [
                        "groupingVariable", "group", "groupVariable",
                        "factor", "fixedFactor",
                    ]
                    if _options_contain_var(opts, "Gender", group_fields):
                        mw_correct_group = True
                    elif _options_json_contains(opts, "gender"):
                        mw_correct_group = True

                    if opts.get("descriptives") or opts.get("descriptivesTable"):
                        mw_has_descriptives = True
                    elif _options_json_contains(opts, "descriptiv"):
                        mw_has_descriptives = True

                    if opts.get("effectSize") or opts.get("effectSizeConfidenceInterval"):
                        mw_has_effect_size = True
                    elif _options_json_contains(opts, "effectsize"):
                        mw_has_effect_size = True
                    elif _options_json_contains(opts, "rankbiserial"):
                        mw_has_effect_size = True

            if mw_found and mw_correct_dv and mw_correct_group:
                pts = 18
                extras = []
                if mw_has_descriptives:
                    pts += 3
                    extras.append("descriptives")
                if mw_has_effect_size:
                    pts += 4
                    extras.append("effect size")
                pts = min(pts, 25)
                extra_str = " + " + ", ".join(extras) if extras else ""
                score += pts
                feedback.append("C2 ({}/25): Mann-Whitney U with correct DV and grouping{}".format(pts, extra_str))
            elif mw_found and (mw_correct_dv or mw_correct_group):
                score += 12
                detail = "DV" if mw_correct_dv else "grouping var"
                feedback.append("C2 (12/25): Mann-Whitney U found with correct {} only".format(detail))
            elif mw_found:
                score += 7
                feedback.append("C2 (7/25): Mann-Whitney U found but variables not correctly assigned")
            else:
                feedback.append("C2 (0/25): No Mann-Whitney U test found")
        except Exception as e:
            feedback.append("C2 (0/25): Error: {}".format(e))

        # ==============================================================
        # Criterion 3 (20 pts): Descriptives with Heart Rate split by Group + plots
        # ==============================================================
        try:
            desc_found = False
            desc_has_hr = False
            desc_split_by_group = False
            desc_has_plots = False

            for analysis in analyses_list:
                aname = _normalize(analysis.get("name", ""))
                opts = analysis.get("options", {})

                is_desc = any(kw in aname for kw in [
                    "descriptiv", "descriptivestatistics",
                ])

                if is_desc:
                    desc_found = True

                    var_fields = [
                        "variables", "variable", "dependentVariables",
                        "dependent",
                    ]
                    if _options_contain_var(opts, "Heart Rate", var_fields):
                        desc_has_hr = True
                    elif _options_json_contains(opts, "heart rate"):
                        desc_has_hr = True

                    split_fields = [
                        "splitBy", "splitby", "splitVariable",
                        "groupingVariable", "factor",
                    ]
                    if _options_contain_var(opts, "Group", split_fields):
                        desc_split_by_group = True
                    for key in opts:
                        if "split" in key.lower():
                            val = opts[key]
                            if isinstance(val, str) and _normalize(val) == "group":
                                desc_split_by_group = True
                            elif isinstance(val, list):
                                for item in val:
                                    if isinstance(item, str) and _normalize(item) == "group":
                                        desc_split_by_group = True

                    desc_has_plots = _check_plots_enabled(opts)

            if desc_found and desc_has_hr and desc_split_by_group:
                if desc_has_plots:
                    score += 20
                    feedback.append("C3 (20/20): Descriptives with Heart Rate split by Group + plots")
                else:
                    score += 14
                    feedback.append("C3 (14/20): Descriptives with Heart Rate split by Group, no plots")
            elif desc_found and desc_has_hr:
                if desc_has_plots:
                    score += 12
                    feedback.append("C3 (12/20): Descriptives with Heart Rate + plots but not split by Group")
                else:
                    score += 8
                    feedback.append("C3 (8/20): Descriptives with Heart Rate but not split by Group, no plots")
            elif desc_found:
                score += 5
                feedback.append("C3 (5/20): Descriptives found but Heart Rate not assigned correctly")
            else:
                feedback.append("C3 (0/20): No Descriptive Statistics analysis found")
        except Exception as e:
            feedback.append("C3 (0/20): Error: {}".format(e))

        # ==============================================================
        # Criterion 4 (15 pts): At least 3 distinct analyses
        # ==============================================================
        try:
            num_analyses = len(analyses_list)
            if num_analyses >= 3:
                score += 15
                feedback.append("C4 (15/15): {} analyses configured".format(num_analyses))
            elif num_analyses == 2:
                score += 8
                feedback.append("C4 (8/15): Only {} analyses (need 3)".format(num_analyses))
            elif num_analyses == 1:
                score += 4
                feedback.append("C4 (4/15): Only 1 analysis (need 3)")
            else:
                feedback.append("C4 (0/15): No analyses found")
        except Exception as e:
            feedback.append("C4 (0/15): Error: {}".format(e))

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

            if file_size > 50000 and has_results and result_count >= 3:
                score += 15
                feedback.append(
                    "C5 (15/15): Substantial file ({} bytes, {} result files)".format(
                        file_size, result_count))
            elif file_size > 20000 and has_results:
                score += 12
                feedback.append(
                    "C5 (12/15): File with results ({} bytes, {} result files)".format(
                        file_size, result_count))
            elif file_size > 5000 and has_results:
                score += 8
                feedback.append("C5 (8/15): Moderate file with results ({} bytes)".format(file_size))
            elif file_size > 5000:
                score += 5
                feedback.append("C5 (5/15): File present ({} bytes) but no result files".format(file_size))
            elif file_size > 0:
                score += 2
                feedback.append("C5 (2/15): Minimal file ({} bytes)".format(file_size))
            else:
                feedback.append("C5 (0/15): File empty or not found")
        except Exception as e:
            feedback.append("C5 (0/15): Error: {}".format(e))

        # ==============================================================
        # Final result
        # ==============================================================
        passed = score >= PASS_THRESHOLD

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback),
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
