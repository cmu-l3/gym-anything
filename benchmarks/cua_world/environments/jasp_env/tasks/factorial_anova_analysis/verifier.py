#!/usr/bin/env python3
"""
Verifier for the factorial_anova_analysis task.

Parses the saved .jasp file (a ZIP archive) and inspects analyses.json
to confirm the agent configured a two-way ANOVA with the required options.

Scoring (100 points total):
  Criterion 1 (25 pts): ANOVA analysis with correct DV (len) and factors (supp, dose)
  Criterion 2 (20 pts): Post-hoc comparisons enabled for dose factor
  Criterion 3 (20 pts): Descriptive statistics enabled
  Criterion 4 (20 pts): Descriptive/interaction plots enabled
  Criterion 5 (15 pts): File is substantial with computed results

Pass threshold: 70 points
"""

import json
import logging
import os
import tempfile
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

JASP_OUTPUT_PATH = "/home/ga/Documents/JASP/tooth_growth_anova.jasp"
PASS_THRESHOLD = 70


def _extract_jasp_analyses(jasp_path):
    """Extract and parse analyses.json from a .jasp file (ZIP archive).

    Returns:
        tuple: (analyses_list, file_size, resource_count, error_string)
    """
    if not os.path.isfile(jasp_path):
        return None, 0, 0, f"File not found: {jasp_path}"

    file_size = os.path.getsize(jasp_path)

    tmpdir = tempfile.mkdtemp(prefix="jasp_verify_")
    try:
        with zipfile.ZipFile(jasp_path, "r") as zf:
            zf.extractall(tmpdir)

        analyses_path = os.path.join(tmpdir, "analyses.json")
        if not os.path.isfile(analyses_path):
            return None, file_size, 0, "analyses.json not found in .jasp archive"

        with open(analyses_path, "r") as f:
            data = json.load(f)

        # Normalise to a list of analysis dicts
        if isinstance(data, list):
            analyses = data
        elif isinstance(data, dict) and "analyses" in data:
            analyses = data["analyses"]
        else:
            analyses = [data] if isinstance(data, dict) else []

        # Count resource files (computed results)
        resource_count = 0
        resources_dir = os.path.join(tmpdir, "resources")
        if os.path.isdir(resources_dir):
            for root, _dirs, files in os.walk(resources_dir):
                for fname in files:
                    if fname.endswith(".json"):
                        resource_count += 1

        return analyses, file_size, resource_count, None

    except zipfile.BadZipFile:
        return None, file_size, 0, "Invalid ZIP / .jasp file"
    except json.JSONDecodeError as exc:
        return None, file_size, 0, f"analyses.json is invalid JSON: {exc}"
    except Exception as exc:
        return None, file_size, 0, f"Unexpected error: {exc}"


def _find_anova_analysis(analyses):
    """Find the first ANOVA-type analysis in the list.

    JASP uses analysis types like 'Anova', 'AnovaExact', etc. and the
    module is typically 'jaspAnova'.  We accept any analysis whose type
    contains 'nova' (case-insensitive) or whose module contains 'Anova'.
    """
    if not analyses:
        return None

    for analysis in analyses:
        if not isinstance(analysis, dict):
            continue

        atype = str(analysis.get("analysisType", analysis.get("type", ""))).lower()
        module = str(analysis.get("module", "")).lower()
        name = str(analysis.get("name", "")).lower()

        if "anova" in atype or "anova" in module or "anova" in name:
            return analysis

    return None


def verify_factorial_anova_analysis(traj, env_info, task_info):
    """Verify that the agent created a proper factorial ANOVA analysis.

    This function is called by the Gym-Anything runner after the task
    completes.  It returns a dict with keys: passed, score, feedback.
    """
    score = 0
    max_score = 100
    feedback_parts = []

    # -----------------------------------------------------------------
    # Gate: does the .jasp file exist at all?
    # -----------------------------------------------------------------
    # The export_result.sh may have also written /tmp/factorial_anova_result.json,
    # but we re-parse from the .jasp file directly for robustness.
    # Also try to get the file via copy_from_env if available.
    jasp_path = JASP_OUTPUT_PATH
    copy_from_env = env_info.get("copy_from_env")
    local_jasp_path = None

    if copy_from_env:
        try:
            tmpdir = tempfile.mkdtemp(prefix="jasp_verify_copy_")
            local_jasp_path = os.path.join(tmpdir, "tooth_growth_anova.jasp")
            copy_from_env(JASP_OUTPUT_PATH, local_jasp_path)
            jasp_path = local_jasp_path
        except Exception as exc:
            logger.warning("copy_from_env failed: %s, trying local path", exc)
            jasp_path = JASP_OUTPUT_PATH

    if not os.path.isfile(jasp_path):
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "No .jasp output file found. The agent must save the analysis as "
                f"'{JASP_OUTPUT_PATH}'."
            ),
        }

    # -----------------------------------------------------------------
    # Extract analyses from the .jasp archive
    # -----------------------------------------------------------------
    analyses, file_size, resource_count, error = _extract_jasp_analyses(jasp_path)

    if error:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not parse .jasp file: {error}",
        }

    if not analyses:
        return {
            "passed": False,
            "score": 0,
            "feedback": "The .jasp file contains no analyses.",
        }

    # -----------------------------------------------------------------
    # Find the ANOVA analysis
    # -----------------------------------------------------------------
    anova = _find_anova_analysis(analyses)

    if anova is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"No ANOVA analysis found among {len(analyses)} analysis/es. "
                "The agent must create an ANOVA analysis in JASP."
            ),
        }

    options = anova.get("options", {})
    if not isinstance(options, dict):
        options = {}

    # =================================================================
    # WRONG-TARGET GATE: DV must be 'len'
    # =================================================================
    dv = options.get("dependent", options.get("dependentVariable", ""))
    if isinstance(dv, str):
        dv_lower = dv.strip().lower()
    else:
        dv_lower = ""

    if dv_lower != "len":
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong target: ANOVA dependent variable is '{dv}', expected 'len'. "
                "Analysis is fundamentally wrong."
            ),
        }

    # =================================================================
    # Criterion 1 (25 pts): Correct DV and both fixed factors
    # =================================================================
    try:
        fixed_factors = options.get("fixedFactors", [])

        factor_names = set()
        if isinstance(fixed_factors, list):
            for f in fixed_factors:
                if isinstance(f, str):
                    factor_names.add(f.strip().lower())
                elif isinstance(f, dict) and "value" in f:
                    factor_names.add(str(f["value"]).strip().lower())

        has_supp = "supp" in factor_names
        has_dose = "dose" in factor_names

        if has_supp and has_dose:
            score += 25
            feedback_parts.append(
                "Criterion 1 (25/25): ANOVA with correct DV ('len') and both factors ('supp', 'dose')"
            )
        elif has_supp or has_dose:
            score += 12
            missing = "dose" if not has_dose else "supp"
            feedback_parts.append(
                f"Criterion 1 (12/25): Correct DV but missing factor '{missing}'"
            )
        else:
            score += 8
            feedback_parts.append(
                "Criterion 1 (8/25): Correct DV but no fixed factors assigned"
            )
    except Exception as exc:
        feedback_parts.append(f"Criterion 1 (0/25): Error checking DV/factors: {exc}")

    # =================================================================
    # Criterion 2 (20 pts): Post-hoc comparisons enabled for dose
    # =================================================================
    try:
        post_hoc = options.get("postHocTerms", options.get("postHocTestsVariables", []))
        post_hoc_enabled = False

        if isinstance(post_hoc, list):
            for item in post_hoc:
                # post_hoc items can be strings or lists/dicts
                if isinstance(item, str) and item.strip().lower() == "dose":
                    post_hoc_enabled = True
                    break
                elif isinstance(item, list):
                    # JASP sometimes encodes terms as nested lists, e.g. [["dose"]]
                    flat = [str(x).strip().lower() for x in item]
                    if "dose" in flat:
                        post_hoc_enabled = True
                        break
                elif isinstance(item, dict):
                    components = item.get("components", item.get("value", []))
                    if isinstance(components, list):
                        flat = [str(x).strip().lower() for x in components]
                        if "dose" in flat:
                            post_hoc_enabled = True
                            break
                    elif isinstance(components, str) and components.strip().lower() == "dose":
                        post_hoc_enabled = True
                        break

        if post_hoc_enabled:
            score += 20
            feedback_parts.append(
                "Criterion 2 (20/20): Post-hoc comparisons enabled for 'dose'"
            )
        else:
            # Check if post-hoc is enabled for ANY factor (partial credit)
            if isinstance(post_hoc, list) and len(post_hoc) > 0:
                score += 8
                feedback_parts.append(
                    f"Criterion 2 (8/20): Post-hoc enabled but not specifically for 'dose' "
                    f"(found: {post_hoc})"
                )
            else:
                feedback_parts.append(
                    "Criterion 2 (0/20): Post-hoc comparisons not enabled"
                )
    except Exception as exc:
        feedback_parts.append(f"Criterion 2 (0/20): Error checking post-hoc: {exc}")

    # =================================================================
    # Criterion 3 (20 pts): Descriptive statistics enabled
    # =================================================================
    try:
        descriptives = options.get("descriptives", False)

        if descriptives is True or str(descriptives).lower() == "true":
            score += 20
            feedback_parts.append(
                "Criterion 3 (20/20): Descriptive statistics enabled"
            )
        else:
            # Check alternative keys that JASP might use
            alt_keys = [
                "marginalMeansTerms", "marginalMeanComparedToZero",
                "descriptivesTable", "customContrasts",
            ]
            partial = False
            for key in alt_keys:
                val = options.get(key)
                if val and val is not False:
                    partial = True
                    break

            if partial:
                score += 10
                feedback_parts.append(
                    "Criterion 3 (10/20): Descriptive statistics partially configured"
                )
            else:
                feedback_parts.append(
                    "Criterion 3 (0/20): Descriptive statistics not enabled"
                )
    except Exception as exc:
        feedback_parts.append(f"Criterion 3 (0/20): Error checking descriptives: {exc}")

    # =================================================================
    # Criterion 4 (20 pts): Descriptive / interaction plots enabled
    # =================================================================
    try:
        plots_enabled = False
        partial_plots = False

        # JASP ANOVA descriptive plots can appear in several option keys
        # depending on JASP version and the exact analysis type.
        desc_plots = options.get("descriptivePlots", None)
        plot_h_axis = options.get("plotHorizontalAxis", "")
        plot_sep_lines = options.get("plotSeparateLines", "")
        plot_sep_plots = options.get("plotSeparatePlots", "")

        # Method 1: descriptivePlots is a boolean or object
        if desc_plots is True or str(desc_plots).lower() == "true":
            plots_enabled = True
        elif isinstance(desc_plots, dict):
            # Some JASP versions use a dict with sub-options
            plots_enabled = True

        # Method 2: plotHorizontalAxis is set (means plots section configured)
        if plot_h_axis and str(plot_h_axis).strip():
            plots_enabled = True

        # Method 3: Check for any plot-related options being non-default
        plot_keys = [
            "plotWidthDescriptivesPlotLegend",
            "plotHeightDescriptivesPlotLegend",
            "plotCredibleInterval",
            "plotErrorBars",
            "descriptivePlotErrorBarType",
            "descriptivePlotCiLevel",
        ]
        for pk in plot_keys:
            if pk in options:
                partial_plots = True

        # Method 4: Check for descriptivePlotHorizontalAxis / descriptivePlotSeparateLines
        dp_h = options.get("descriptivePlotHorizontalAxis", "")
        dp_sl = options.get("descriptivePlotSeparateLines", "")
        if dp_h or dp_sl:
            plots_enabled = True

        if plots_enabled:
            # Check if it's truly an interaction plot (both axis and lines set)
            axis_var = str(plot_h_axis or dp_h).strip().lower()
            lines_var = str(plot_sep_lines or dp_sl).strip().lower()

            if axis_var and lines_var:
                score += 20
                feedback_parts.append(
                    f"Criterion 4 (20/20): Interaction plot enabled "
                    f"(axis='{axis_var}', lines='{lines_var}')"
                )
            else:
                score += 14
                feedback_parts.append(
                    "Criterion 4 (14/20): Descriptive plots enabled but interaction "
                    "configuration could not be fully confirmed"
                )
        elif partial_plots:
            score += 8
            feedback_parts.append(
                "Criterion 4 (8/20): Some plot-related options detected but "
                "descriptive plots may not be fully enabled"
            )
        else:
            feedback_parts.append(
                "Criterion 4 (0/20): Descriptive/interaction plots not enabled"
            )
    except Exception as exc:
        feedback_parts.append(f"Criterion 4 (0/20): Error checking plots: {exc}")

    # =================================================================
    # Criterion 5 (15 pts): File is substantial with computed results
    # =================================================================
    try:
        size_ok = file_size >= 5000  # A .jasp with computed ANOVA > 5KB
        has_resources = resource_count >= 1

        if size_ok and has_resources:
            score += 15
            feedback_parts.append(
                f"Criterion 5 (15/15): File substantial ({file_size} bytes, "
                f"{resource_count} resource files)"
            )
        elif size_ok:
            score += 10
            feedback_parts.append(
                f"Criterion 5 (10/15): File size OK ({file_size} bytes) but "
                f"no computed resource files found"
            )
        elif has_resources:
            score += 8
            feedback_parts.append(
                f"Criterion 5 (8/15): Resource files present ({resource_count}) "
                f"but file size small ({file_size} bytes)"
            )
        else:
            score += 3 if file_size > 1000 else 0
            feedback_parts.append(
                f"Criterion 5 ({3 if file_size > 1000 else 0}/15): File may not "
                f"contain computed results ({file_size} bytes, "
                f"{resource_count} resources)"
            )
    except Exception as exc:
        feedback_parts.append(f"Criterion 5 (0/15): Error checking file: {exc}")

    # =================================================================
    # Also check for eta-squared (bonus info, not separate criterion
    # but noted in feedback)
    # =================================================================
    try:
        eta_sq = options.get("effectSizeEtaSquared", False)
        if eta_sq is True or str(eta_sq).lower() == "true":
            feedback_parts.append("Bonus: Eta-squared effect size enabled")
        else:
            feedback_parts.append(
                "Note: Eta-squared not detected (may affect analysis completeness)"
            )
    except Exception:
        pass

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
