#!/usr/bin/env python3
"""
Verifier for exploratory_data_analysis task (jasp_env).

Parses the saved .jasp file (a ZIP archive) and inspects analyses.json to verify
that the agent correctly configured Descriptive Statistics, Correlation, and
One-Way ANOVA analyses on the Palmer Penguins dataset.

Scoring rubric (100 points total, pass threshold 70):
  Criterion 1 (25 pts): Descriptives analysis with morphometric vars split by species
  Criterion 2 (25 pts): Correlation analysis with morphometric vars + significance
  Criterion 3 (25 pts): ANOVA analysis with body_mass_g DV and species factor + post-hoc
  Criterion 4 (10 pts): At least 3 distinct analyses present
  Criterion 5 (15 pts): File substantial with computed results
"""

import json
import logging
import os
import tempfile
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_MORPHOMETRIC_VARS = {"bill_length_mm", "bill_depth_mm", "flipper_length_mm", "body_mass_g"}
JASP_OUTPUT_FILE = "/home/ga/Documents/JASP/penguins_eda.jasp"
PASS_THRESHOLD = 70


def _extract_jasp_file(jasp_path, copy_from_env=None):
    """Extract .jasp ZIP archive and return (temp_dir, analyses_data, extract_dir) or raise."""
    temp_dir = tempfile.mkdtemp(prefix="jasp_eda_verify_")

    # If copy_from_env is available, copy the file from the VM first
    local_jasp = os.path.join(temp_dir, "penguins_eda.jasp")
    if copy_from_env:
        try:
            copy_from_env(jasp_path, local_jasp)
        except Exception as e:
            logger.warning(f"copy_from_env failed: {e}, trying local path")
            local_jasp = jasp_path
    else:
        local_jasp = jasp_path

    if not os.path.isfile(local_jasp):
        raise FileNotFoundError(f"JASP output file not found: {jasp_path}")

    file_size = os.path.getsize(local_jasp)
    extract_dir = os.path.join(temp_dir, "extracted")
    os.makedirs(extract_dir, exist_ok=True)

    with zipfile.ZipFile(local_jasp, "r") as zf:
        zf.extractall(extract_dir)

    # Locate analyses.json
    analyses_path = os.path.join(extract_dir, "analyses.json")
    if not os.path.exists(analyses_path):
        # Walk the extracted tree
        for root, dirs, files in os.walk(extract_dir):
            if "analyses.json" in files:
                analyses_path = os.path.join(root, "analyses.json")
                break

    if not os.path.exists(analyses_path):
        raise FileNotFoundError("analyses.json not found inside .jasp archive")

    with open(analyses_path, "r") as f:
        analyses_data = json.load(f)

    return temp_dir, analyses_data, extract_dir, file_size


def _get_analyses_list(analyses_data):
    """Normalise the top-level structure to a list of analysis dicts."""
    if isinstance(analyses_data, dict):
        return analyses_data.get("analyses", [])
    elif isinstance(analyses_data, list):
        return analyses_data
    return []


def _collect_vars_from_options(options, key_names):
    """Recursively collect variable names mentioned under given option keys."""
    found = set()
    if not isinstance(options, dict):
        return found

    for key in key_names:
        val = options.get(key)
        if isinstance(val, list):
            for item in val:
                if isinstance(item, str):
                    found.add(item)
                elif isinstance(item, dict):
                    # e.g. {"name": "bill_length_mm", ...}
                    name = item.get("name") or item.get("variable") or item.get("value")
                    if name:
                        found.add(str(name))
        elif isinstance(val, str) and val:
            found.add(val)

    return found


def _deep_search_for_vars(obj, depth=0, max_depth=8):
    """Recursively search a nested dict/list for strings matching expected variable names."""
    found = set()
    if depth > max_depth:
        return found

    if isinstance(obj, str):
        if obj in EXPECTED_MORPHOMETRIC_VARS:
            found.add(obj)
    elif isinstance(obj, list):
        for item in obj:
            found |= _deep_search_for_vars(item, depth + 1, max_depth)
    elif isinstance(obj, dict):
        for v in obj.values():
            found |= _deep_search_for_vars(v, depth + 1, max_depth)

    return found


def _deep_search_for_key(obj, target_key, depth=0, max_depth=8):
    """Recursively search for a specific key and return its value."""
    if depth > max_depth:
        return None

    if isinstance(obj, dict):
        if target_key in obj:
            return obj[target_key]
        for v in obj.values():
            result = _deep_search_for_key(v, target_key, depth + 1, max_depth)
            if result is not None:
                return result
    elif isinstance(obj, list):
        for item in obj:
            result = _deep_search_for_key(item, target_key, depth + 1, max_depth)
            if result is not None:
                return result

    return None


def _is_descriptives_analysis(analysis):
    """Check if an analysis dict looks like a Descriptives analysis."""
    module = str(analysis.get("module", "")).lower()
    name = str(analysis.get("name", "")).lower()
    analysis_name = str(analysis.get("analysisName", "")).lower()

    return any(
        "descriptive" in s
        for s in [module, name, analysis_name]
    )


def _is_correlation_analysis(analysis):
    """Check if an analysis dict looks like a Correlation analysis."""
    module = str(analysis.get("module", "")).lower()
    name = str(analysis.get("name", "")).lower()
    analysis_name = str(analysis.get("analysisName", "")).lower()

    return any(
        "correlation" in s or "corr" in s
        for s in [module, name, analysis_name]
    )


def _is_anova_analysis(analysis):
    """Check if an analysis dict looks like an ANOVA analysis."""
    module = str(analysis.get("module", "")).lower()
    name = str(analysis.get("name", "")).lower()
    analysis_name = str(analysis.get("analysisName", "")).lower()

    return any(
        "anova" in s
        for s in [module, name, analysis_name]
    )


def verify_exploratory_data_analysis(traj, env_info, task_info):
    """
    Verify the exploratory_data_analysis task.

    Criteria:
      1. (25 pts) Descriptives with 4 morphometric vars split by species
      2. (25 pts) Correlation with 4 morphometric vars + significance flagging
      3. (25 pts) ANOVA with body_mass_g DV, species factor, and Tukey post-hoc
      4. (10 pts) At least 3 distinct analyses present
      5. (15 pts) File substantial with computed results

    Pass threshold: 70/100
    """
    copy_from_env = env_info.get("copy_from_env")
    score = 0
    feedback_parts = []
    temp_dir = None

    # ==================================================================
    # Output-existence gate
    # ==================================================================
    try:
        temp_dir, analyses_data, extract_dir, file_size = _extract_jasp_file(
            JASP_OUTPUT_FILE, copy_from_env
        )
    except FileNotFoundError as e:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Output file not found or could not be extracted: {e}",
        }
    except zipfile.BadZipFile:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "Output file exists but is not a valid ZIP/.jasp archive",
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Error accessing output file: {e}",
        }

    try:
        analyses_list = _get_analyses_list(analyses_data)
        logger.info(f"Found {len(analyses_list)} analyses in .jasp file ({file_size} bytes)")

        # ==============================================================
        # WRONG-TARGET GATE: At least one analysis must reference
        # morphometric variables
        # ==============================================================
        any_morpho_reference = False
        for analysis in analyses_list:
            opts = analysis.get("options", {})
            found_vars = _deep_search_for_vars(opts)
            if found_vars & EXPECTED_MORPHOMETRIC_VARS:
                any_morpho_reference = True
                break

        if not any_morpho_reference:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Wrong target: No analysis references any of the expected "
                            "morphometric variables (bill_length_mm, bill_depth_mm, "
                            "flipper_length_mm, body_mass_g). Analysis is fundamentally wrong.",
            }

        # ==============================================================
        # Criterion 1 (25 pts): Descriptives analysis
        # ==============================================================
        try:
            desc_analyses = [a for a in analyses_list if _is_descriptives_analysis(a)]
            c1_score = 0

            if desc_analyses:
                desc = desc_analyses[0]
                options = desc.get("options", {})

                # Check variables assigned
                var_keys = ["variables", "vars", "variable", "selectedVariables"]
                found_vars = _collect_vars_from_options(options, var_keys)
                if not found_vars:
                    found_vars = _deep_search_for_vars(options)

                morpho_match = found_vars & EXPECTED_MORPHOMETRIC_VARS
                if len(morpho_match) >= 4:
                    c1_score += 10
                    feedback_parts.append("Descriptives: all 4 morphometric variables assigned")
                elif len(morpho_match) >= 2:
                    c1_score += 5
                    feedback_parts.append(
                        f"Descriptives: only {len(morpho_match)}/4 morphometric variables assigned"
                    )
                else:
                    feedback_parts.append("Descriptives: morphometric variables not properly assigned")

                # Check split by species
                split_keys = ["splitBy", "splitby", "split", "groupingVariable", "groupBy"]
                split_vars = _collect_vars_from_options(options, split_keys)
                if not split_vars:
                    # Deep search for "species" anywhere in options
                    all_vars_in_opts = _deep_search_for_vars(options)
                    if "species" in all_vars_in_opts:
                        split_vars = {"species"}

                if "species" in split_vars:
                    c1_score += 10
                    feedback_parts.append("Descriptives: split by species correctly configured")
                else:
                    feedback_parts.append("Descriptives: split by species not found")

                # Check that statistics or plots are enabled (partial credit)
                # Look for mean, std, median, min, max, or distribution plots
                opts_str = json.dumps(options).lower()
                stats_enabled = any(
                    kw in opts_str
                    for kw in ["mean", "standarddeviation", "std", "median", "minimum", "maximum",
                               "distributionplot", "histogram"]
                )
                if stats_enabled:
                    c1_score += 5
                    feedback_parts.append("Descriptives: statistics/plots options detected")
                else:
                    feedback_parts.append("Descriptives: could not confirm statistics/plots enabled")

            else:
                feedback_parts.append("Descriptives: analysis NOT found in file")

            score += c1_score
            logger.info(f"Criterion 1 (Descriptives): {c1_score}/25")

        except Exception as e:
            logger.error(f"Criterion 1 error: {e}", exc_info=True)
            feedback_parts.append(f"Descriptives: verification error ({e})")

        # ==============================================================
        # Criterion 2 (25 pts): Correlation analysis
        # ==============================================================
        try:
            corr_analyses = [a for a in analyses_list if _is_correlation_analysis(a)]
            c2_score = 0

            if corr_analyses:
                corr = corr_analyses[0]
                options = corr.get("options", {})

                # Check variables
                var_keys = ["variables", "vars", "variable", "selectedVariables"]
                found_vars = _collect_vars_from_options(options, var_keys)
                if not found_vars:
                    found_vars = _deep_search_for_vars(options)

                morpho_match = found_vars & EXPECTED_MORPHOMETRIC_VARS
                if len(morpho_match) >= 4:
                    c2_score += 10
                    feedback_parts.append("Correlation: all 4 morphometric variables assigned")
                elif len(morpho_match) >= 2:
                    c2_score += 5
                    feedback_parts.append(
                        f"Correlation: only {len(morpho_match)}/4 morphometric variables assigned"
                    )
                else:
                    feedback_parts.append("Correlation: morphometric variables not properly assigned")

                # Check significance flagging
                opts_str = json.dumps(options).lower()
                has_significance = any(
                    kw in opts_str
                    for kw in ["significance", "flagsignificant", "flag_significant",
                               "reportsignificance", "report_significance", "significantflag",
                               "reportpvalue", "pvalue"]
                )
                if has_significance:
                    c2_score += 8
                    feedback_parts.append("Correlation: significance reporting detected")
                else:
                    # Check for Pearson being enabled (which implies significance is available)
                    has_pearson = "pearson" in opts_str
                    if has_pearson:
                        c2_score += 4
                        feedback_parts.append(
                            "Correlation: Pearson enabled but significance flag not confirmed"
                        )
                    else:
                        feedback_parts.append("Correlation: significance/Pearson settings not found")

                # Check heatmap plot
                has_heatmap = any(
                    kw in opts_str
                    for kw in ["heatmap", "heat_map", "correlationplot", "plotcorrelation",
                               "plotmatrix"]
                )
                if has_heatmap:
                    c2_score += 7
                    feedback_parts.append("Correlation: heatmap plot detected")
                else:
                    # Check for any plot being enabled
                    has_any_plot = "plot" in opts_str
                    if has_any_plot:
                        c2_score += 3
                        feedback_parts.append(
                            "Correlation: some plot detected but heatmap not confirmed"
                        )
                    else:
                        feedback_parts.append("Correlation: heatmap/plot not found")

            else:
                feedback_parts.append("Correlation: analysis NOT found in file")

            score += c2_score
            logger.info(f"Criterion 2 (Correlation): {c2_score}/25")

        except Exception as e:
            logger.error(f"Criterion 2 error: {e}", exc_info=True)
            feedback_parts.append(f"Correlation: verification error ({e})")

        # ==============================================================
        # Criterion 3 (25 pts): ANOVA analysis
        # ==============================================================
        try:
            anova_analyses = [a for a in analyses_list if _is_anova_analysis(a)]
            c3_score = 0

            if anova_analyses:
                anova = anova_analyses[0]
                options = anova.get("options", {})

                # Check dependent variable is body_mass_g
                dv_keys = ["dependent", "dependentVariable", "dependentVariables",
                           "dependent_variable", "dv", "response"]
                dv_vars = _collect_vars_from_options(options, dv_keys)
                if not dv_vars:
                    dv_val = _deep_search_for_key(options, "dependent")
                    if isinstance(dv_val, str) and dv_val:
                        dv_vars = {dv_val}
                    elif isinstance(dv_val, list):
                        dv_vars = {str(v) for v in dv_val if v}

                if "body_mass_g" in dv_vars:
                    c3_score += 8
                    feedback_parts.append("ANOVA: body_mass_g set as dependent variable")
                else:
                    feedback_parts.append(
                        f"ANOVA: dependent variable not body_mass_g (found: {dv_vars})"
                    )

                # Check fixed factor is species
                factor_keys = ["fixedFactors", "fixed_factors", "factor", "factors",
                               "fixedFactor", "between", "betweenSubjectFactors",
                               "independentVariable"]
                factor_vars = _collect_vars_from_options(options, factor_keys)
                if not factor_vars:
                    factor_val = _deep_search_for_key(options, "fixedFactors")
                    if isinstance(factor_val, str) and factor_val:
                        factor_vars = {factor_val}
                    elif isinstance(factor_val, list):
                        for item in factor_val:
                            if isinstance(item, str):
                                factor_vars.add(item)
                            elif isinstance(item, dict):
                                name = item.get("name") or item.get("value") or item.get("variable")
                                if name:
                                    factor_vars.add(str(name))

                if "species" in factor_vars:
                    c3_score += 7
                    feedback_parts.append("ANOVA: species set as fixed factor")
                else:
                    feedback_parts.append(
                        f"ANOVA: fixed factor not species (found: {factor_vars})"
                    )

                # Check post-hoc (Tukey)
                opts_str = json.dumps(options).lower()
                has_posthoc = any(
                    kw in opts_str
                    for kw in ["posthoc", "post_hoc", "posthocc", "tukey",
                               "posthoctests", "post-hoc"]
                )
                # Also check if species appears in a postHocTerms-like key
                posthoc_keys = ["postHocTerms", "postHocTestsVariables",
                                "postHocTestTerms", "posthoc"]
                posthoc_vars = _collect_vars_from_options(options, posthoc_keys)
                if not posthoc_vars:
                    posthoc_val = _deep_search_for_key(options, "postHocTerms")
                    if posthoc_val:
                        posthoc_vars_deep = _deep_search_for_vars(
                            posthoc_val if isinstance(posthoc_val, (dict, list)) else {}
                        )
                        if "species" in posthoc_vars_deep:
                            posthoc_vars = {"species"}

                if "species" in posthoc_vars or has_posthoc:
                    c3_score += 5
                    feedback_parts.append("ANOVA: post-hoc (Tukey) detected")
                else:
                    feedback_parts.append("ANOVA: post-hoc comparisons not found")

                # Check descriptive statistics enabled
                has_descriptives = any(
                    kw in opts_str
                    for kw in ["descriptive", "descriptivestatistics", "descriptives",
                               "descriptivesstatistics"]
                )
                if has_descriptives:
                    c3_score += 5
                    feedback_parts.append("ANOVA: descriptive statistics enabled")
                else:
                    feedback_parts.append("ANOVA: descriptive statistics not confirmed")

            else:
                feedback_parts.append("ANOVA: analysis NOT found in file")

            score += c3_score
            logger.info(f"Criterion 3 (ANOVA): {c3_score}/25")

        except Exception as e:
            logger.error(f"Criterion 3 error: {e}", exc_info=True)
            feedback_parts.append(f"ANOVA: verification error ({e})")

        # ==============================================================
        # Criterion 4 (10 pts): At least 3 distinct analyses
        # ==============================================================
        try:
            c4_score = 0
            num_analyses = len(analyses_list)

            if num_analyses >= 3:
                # Check they are distinct types
                type_set = set()
                for a in analyses_list:
                    if _is_descriptives_analysis(a):
                        type_set.add("descriptives")
                    elif _is_correlation_analysis(a):
                        type_set.add("correlation")
                    elif _is_anova_analysis(a):
                        type_set.add("anova")
                    else:
                        type_set.add(
                            a.get("analysisName", a.get("name", "other")).lower()
                        )

                if len(type_set) >= 3:
                    c4_score = 10
                    feedback_parts.append(
                        f"Multi-analysis: {num_analyses} analyses of {len(type_set)} distinct types"
                    )
                elif len(type_set) >= 2:
                    c4_score = 5
                    feedback_parts.append(
                        f"Multi-analysis: {num_analyses} analyses but only {len(type_set)} distinct types"
                    )
                else:
                    c4_score = 2
                    feedback_parts.append(
                        f"Multi-analysis: {num_analyses} analyses but all same type"
                    )
            elif num_analyses >= 2:
                c4_score = 4
                feedback_parts.append(f"Multi-analysis: only {num_analyses} analyses found (need 3+)")
            elif num_analyses == 1:
                c4_score = 1
                feedback_parts.append("Multi-analysis: only 1 analysis found")
            else:
                feedback_parts.append("Multi-analysis: no analyses found in file")

            score += c4_score
            logger.info(f"Criterion 4 (Multi-analysis): {c4_score}/10")

        except Exception as e:
            logger.error(f"Criterion 4 error: {e}", exc_info=True)
            feedback_parts.append(f"Multi-analysis: verification error ({e})")

        # ==============================================================
        # Criterion 5 (15 pts): File substantial with computed results
        # ==============================================================
        try:
            c5_score = 0

            # Check file size is substantial (a .jasp with 3 analyses + results
            # should be at least several KB, typically 50-500+ KB)
            if file_size >= 50000:
                c5_score += 5
                feedback_parts.append(f"File size: {file_size} bytes (substantial)")
            elif file_size >= 10000:
                c5_score += 3
                feedback_parts.append(f"File size: {file_size} bytes (moderate)")
            elif file_size >= 2000:
                c5_score += 1
                feedback_parts.append(f"File size: {file_size} bytes (small)")
            else:
                feedback_parts.append(f"File size: {file_size} bytes (too small)")

            # Check for computed results in resources/ directory
            resources_dir = os.path.join(extract_dir, "resources")
            result_file_count = 0
            has_jasp_results = False

            if os.path.isdir(resources_dir):
                for root, dirs, files in os.walk(resources_dir):
                    for f in files:
                        result_file_count += 1
                        if "jaspresults" in f.lower() or f.endswith(".json"):
                            has_jasp_results = True

            if has_jasp_results and result_file_count >= 3:
                c5_score += 7
                feedback_parts.append(
                    f"Computed results: {result_file_count} result files with jaspResults"
                )
            elif result_file_count >= 1:
                c5_score += 4
                feedback_parts.append(
                    f"Computed results: {result_file_count} result files found"
                )
            else:
                feedback_parts.append("Computed results: no result files in resources/")

            # Check for data file inside the archive (indicates dataset was loaded)
            data_files = []
            for root, dirs, files in os.walk(extract_dir):
                for f in files:
                    if f.endswith(".csv") or f == "data.json" or f == "dataSet.json":
                        data_files.append(f)

            if data_files:
                c5_score += 3
                feedback_parts.append(f"Data embedded: {data_files}")
            else:
                feedback_parts.append("Data: no embedded dataset found (may be normal)")

            score += c5_score
            logger.info(f"Criterion 5 (File substance): {c5_score}/15")

        except Exception as e:
            logger.error(f"Criterion 5 error: {e}", exc_info=True)
            feedback_parts.append(f"File substance: verification error ({e})")

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
            "score": 0.0,
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
