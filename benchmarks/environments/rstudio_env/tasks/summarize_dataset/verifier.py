#!/usr/bin/env python3
"""
Verifier for summarize_dataset task.

Verification Strategy (Hybrid: Programmatic + R Execution + VLM):

Programmatic checks (35 points) - from export script JSON:
  1. Output CSV file exists (5 pts)
  2. Output was created during task (5 pts)
  3. Output has correct row count (5 pts)
  4. Has exact required columns (10 pts)
  5. Script contains actual R code with dplyr (10 pts)

R Execution verification (35 points) - actually run the script:
  6. R script executes without syntax errors (15 pts)
  7. R script produces correct output when run fresh (20 pts)

Data validation (30 points) - verify numeric accuracy:
  8. All 3 species present with correct names (10 pts)
  9. Mean values are within expected ranges (10 pts)
  10. SD values are within expected ranges (10 pts)

Adversarial detection:
  - Reject hardcoded/pre-computed output
  - Verify R code actually produces the output
  - Validate numeric values against expected ranges (not just existence)
  - Cross-validate script logic with output

Pass threshold: 60 points AND (R execution verified OR data values correct)
"""

import json
import tempfile
import os
import csv
import re
import logging

logger = logging.getLogger(__name__)


# Expected values from Palmer Penguins dataset
# These are computed from the actual dataset and used for validation
# Tolerance tightened to 10% to prevent hardcoded approximate values
EXPECTED_VALUES = {
    'Adelie': {'mean_mass': 3700.66, 'sd_mass': 458.57, 'tolerance': 0.10},
    'Chinstrap': {'mean_mass': 3733.09, 'sd_mass': 384.34, 'tolerance': 0.10},
    'Gentoo': {'mean_mass': 5076.02, 'sd_mass': 504.12, 'tolerance': 0.10},
}


# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_PROCESS_PROMPT = """You are analyzing screenshots from an agent performing data analysis in RStudio.

The task requires using dplyr to create a summary table grouped by species. Look for evidence of:
1. RStudio open with an R script file
2. R code being written (not just comments)
3. Console output showing dplyr operations or data frames
4. A summary table visible in console or viewer

Assess:
- SCRIPT_WRITING: Did the agent write R code with dplyr/group_by/summarize?
- CODE_EXECUTION: Is there evidence the code was run (console output)?
- DATA_PROCESSING: Is there any evidence of data manipulation (not just file browsing)?

Respond in JSON format:
{
    "script_writing_visible": true/false,
    "code_execution_visible": true/false,
    "data_processing_visible": true/false,
    "dplyr_operations_visible": true/false,
    "stages_observed": ["list what you see"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe the workflow you see"
}
"""


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def _vlm_query(query_vlm, prompt, image=None, images=None):
    """Run VLM query. Returns parsed dict or None."""
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


def _is_valid_r_code(script_content):
    """
    Check if script contains actual R code for data summarization.
    Returns (is_valid, code_lines_count, reason)
    """
    if not script_content:
        return False, 0, "Empty script"

    lines = script_content.strip().split('\n')
    code_lines = []

    for line in lines:
        stripped = line.strip()
        # Skip empty lines and comment-only lines
        if not stripped or stripped.startswith('#'):
            continue
        code_lines.append(stripped)

    if len(code_lines) < 3:
        return False, len(code_lines), "Too few code lines (need at least 3)"

    # Check for actual function calls (not just keywords in comments)
    has_read_data = any(re.search(r'read[._]csv\s*\(', line) for line in code_lines)

    # Improved dplyr detection: library(), require(), namespace prefix, pipe operator
    has_dplyr_load = any(re.search(r'(library|require)\s*\(\s*(dplyr|tidyverse)', line) for line in code_lines)
    has_dplyr_namespace = any(re.search(r'dplyr::', line) for line in code_lines)
    has_pipe_operator = any(re.search(r'%>%|\\|>', line) for line in code_lines)  # magrittr or native pipe
    has_dplyr = has_dplyr_load or has_dplyr_namespace or has_pipe_operator

    has_group_by = any(re.search(r'group_by\s*\(', line) for line in code_lines)
    has_summarize = any(re.search(r'summar[iy][sz]e\s*\(', line) for line in code_lines)
    has_write_csv = any(re.search(r'write[._]csv\s*\(', line) for line in code_lines)
    has_assignment = any(re.search(r'<-|=(?!=)', line) for line in code_lines)

    issues = []
    if not has_read_data:
        issues.append("no data loading")
    if not has_dplyr:
        issues.append("dplyr not used (no library/require/namespace/pipe)")
    if not has_group_by:
        issues.append("no group_by()")
    if not has_summarize:
        issues.append("no summarize()")
    if not has_write_csv:
        issues.append("no write.csv()")

    if len(issues) > 2:
        return False, len(code_lines), f"Missing: {', '.join(issues)}"

    return True, len(code_lines), "Valid R code structure"


def _validate_numeric_values(csv_data):
    """
    Validate that numeric values in the CSV match expected Palmer Penguins statistics.
    Returns (is_valid, score, species_results)
    """
    if not csv_data:
        return False, 0, {}

    score = 0
    species_results = {}

    for row in csv_data:
        # Get species name - normalize to title case for comparison
        species = None
        for key in ['species', '"species"', 'Species']:
            if key in row:
                raw_species = row[key].strip().strip('"')
                # Normalize case: "adelie" -> "Adelie", "ADELIE" -> "Adelie"
                species = raw_species.title()
                break

        if not species or species not in EXPECTED_VALUES:
            continue

        expected = EXPECTED_VALUES[species]
        species_results[species] = {'found': True}

        # Get mean value
        mean_val = None
        for key in ['mean_mass', '"mean_mass"', 'mean']:
            if key in row:
                try:
                    mean_val = float(row[key].strip().strip('"'))
                    break
                except (ValueError, TypeError):
                    pass

        # Get sd value
        sd_val = None
        for key in ['sd_mass', '"sd_mass"', 'sd']:
            if key in row:
                try:
                    sd_val = float(row[key].strip().strip('"'))
                    break
                except (ValueError, TypeError):
                    pass

        # Validate mean - tightened tolerance to 10% to catch hardcoded values
        if mean_val is not None:
            expected_mean = expected['mean_mass']
            tolerance_pct = expected['tolerance']  # Now 0.10 (10%)
            if abs(mean_val - expected_mean) < expected_mean * tolerance_pct:  # Within 10%
                species_results[species]['mean_valid'] = True
                score += 3
            elif abs(mean_val - expected_mean) < expected_mean * 0.15:  # Within 15%
                species_results[species]['mean_valid'] = True
                score += 2

        # Validate sd - tightened tolerance to 15% (sd has more variability)
        if sd_val is not None:
            expected_sd = expected['sd_mass']
            if abs(sd_val - expected_sd) < expected_sd * 0.15:  # Within 15%
                species_results[species]['sd_valid'] = True
                score += 2
            elif abs(sd_val - expected_sd) < expected_sd * 0.25:  # Within 25%
                species_results[species]['sd_valid'] = True
                score += 1

    return score >= 10, score, species_results  # Need at least 10/15 points (stricter)


# ================================================================
# MAIN VERIFIER
# ================================================================

def verify_summary(traj, env_info, task_info):
    """
    Verify data summary creation with robust anti-gaming checks.

    Scoring (100 points total):
    - Programmatic (35 pts): file checks, script validation
    - R Execution (35 pts): script actually runs and produces output
    - Data Validation (30 pts): numeric accuracy verification

    Pass threshold: 60 points AND (execution_verified OR data_values_correct)
    """
    copy_from_env = env_info.get('copy_from_env')
    run_in_env = env_info.get('run_in_env')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_columns = metadata.get('expected_columns', ['species', 'mean_mass', 'sd_mass'])
    expected_species = metadata.get('expected_species', ['Adelie', 'Chinstrap', 'Gentoo'])

    feedback_parts = []
    score = 0
    details = {}

    # Flags for key criteria
    execution_verified = False
    data_values_correct = False
    code_is_valid = False

    # ================================================================
    # Load export result JSON from container
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ================================================================
    # Copy and validate the R script
    # ================================================================
    script_content = ""
    script_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.R')
    try:
        copy_from_env("/home/ga/RProjects/summary_analysis.R", script_temp.name)
        with open(script_temp.name, 'r') as f:
            script_content = f.read()
    except Exception:
        pass
    finally:
        if os.path.exists(script_temp.name):
            os.unlink(script_temp.name)

    details['script_length'] = len(script_content)

    # ================================================================
    # Copy and parse the actual CSV
    # ================================================================
    csv_data = None
    csv_headers = []
    csv_valid = False

    csv_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/home/ga/RProjects/output/species_summary.csv", csv_temp.name)
        with open(csv_temp.name, 'r') as f:
            reader = csv.DictReader(f)
            csv_headers = [h.strip().strip('"').lower() for h in reader.fieldnames] if reader.fieldnames else []
            csv_data = list(reader)
            csv_valid = True
    except Exception:
        pass
    finally:
        if os.path.exists(csv_temp.name):
            os.unlink(csv_temp.name)

    # ================================================================
    # PROGRAMMATIC CHECKS (35 points)
    # ================================================================

    # Criterion 1: Output CSV file exists (5 points)
    if result.get('output_exists'):
        score += 5
        feedback_parts.append("Summary CSV exists")
    else:
        feedback_parts.append("FAIL: Summary CSV not found")

    # Criterion 2: Output was created during task (5 points)
    if result.get('output_created'):
        score += 5
        feedback_parts.append("Summary created during task")
    else:
        feedback_parts.append("FAIL: Summary not created during task")

    # Criterion 3: Output has correct row count (5 points)
    output_rows = result.get('output_rows', 0)
    if output_rows >= 4:  # header + 3 species
        score += 5
        feedback_parts.append(f"Output has {output_rows} rows")
    elif output_rows >= 2:
        score += 2
        feedback_parts.append(f"Output has only {output_rows} rows")
    else:
        feedback_parts.append("FAIL: Output is empty")

    # Criterion 4: Has exact required columns (10 points)
    exact_cols_found = sum(1 for col in expected_columns if col.lower() in csv_headers)
    if exact_cols_found == len(expected_columns):
        score += 10
        feedback_parts.append("All required columns present")
    elif exact_cols_found >= 2:
        score += 5
        feedback_parts.append(f"Partial columns found ({exact_cols_found}/3)")
    else:
        feedback_parts.append("FAIL: Missing required columns")

    # Criterion 5: Script contains actual R code (10 points)
    code_valid, code_lines, code_reason = _is_valid_r_code(script_content)
    details['code_validation'] = {'valid': code_valid, 'lines': code_lines, 'reason': code_reason}

    if code_valid:
        score += 10
        feedback_parts.append(f"Valid R code ({code_lines} lines)")
        code_is_valid = True
    elif code_lines > 0:
        score += 4
        feedback_parts.append(f"Incomplete R code: {code_reason}")
    else:
        feedback_parts.append(f"FAIL: Invalid R code - {code_reason}")

    # ================================================================
    # R EXECUTION VERIFICATION (35 points)
    # ================================================================

    if run_in_env and code_is_valid:
        # Remove existing output first
        try:
            run_in_env("rm -f /home/ga/RProjects/output/species_summary_test.csv")
        except Exception:
            pass

        # Create a test script that sources the user's script
        test_script = """
# Test execution of user's summary script
tryCatch({
    # Intercept write.csv to redirect to test location
    original_write_csv <- write.csv
    write.csv <- function(x, file, ...) {
        if (grepl("species_summary", file)) {
            file <- "/home/ga/RProjects/output/species_summary_test.csv"
        }
        original_write_csv(x, file, ...)
    }

    # Source the user's script
    source("/home/ga/RProjects/summary_analysis.R")

    cat("EXECUTION_SUCCESS\\n")
}, error = function(e) {
    cat(paste("EXECUTION_ERROR:", conditionMessage(e), "\\n"))
})
"""

        try:
            run_in_env(f"cat > /tmp/test_summary.R << 'TESTEOF'\n{test_script}\nTESTEOF")
            exec_result = run_in_env("cd /home/ga/RProjects && Rscript /tmp/test_summary.R 2>&1")

            if exec_result and "EXECUTION_SUCCESS" in exec_result:
                # Check if output was created
                test_output_check = run_in_env("ls -la /home/ga/RProjects/output/species_summary_test.csv 2>&1")

                if test_output_check and "No such file" not in test_output_check:
                    # Also verify the test output matches expected format
                    test_content = run_in_env("cat /home/ga/RProjects/output/species_summary_test.csv 2>&1")
                    if test_content and "species" in test_content.lower() and "adelie" in test_content.lower():
                        score += 35
                        feedback_parts.append("R execution verified: script runs and produces correct output")
                        execution_verified = True
                    else:
                        score += 20
                        feedback_parts.append("R script runs but output format unclear")
                else:
                    score += 15
                    feedback_parts.append("R script runs but doesn't produce output")
            elif exec_result and "EXECUTION_ERROR" in exec_result:
                score += 5
                error_msg = exec_result.split("EXECUTION_ERROR:")[-1].strip()[:50]
                feedback_parts.append(f"R script has errors: {error_msg}")
            else:
                feedback_parts.append("R execution check failed")

        except Exception as e:
            logger.warning(f"R execution check exception: {e}")
            feedback_parts.append("R execution check could not run")
    else:
        feedback_parts.append("R execution check skipped")

    # ================================================================
    # DATA VALIDATION (30 points)
    # ================================================================

    # Criterion 8: All 3 species present (10 points)
    # Normalize species names to title case for comparison
    species_found = []
    if csv_data:
        for row in csv_data:
            for key in ['species', '"species"', 'Species']:
                if key in row:
                    raw_species = row[key].strip().strip('"')
                    # Normalize case: "adelie" -> "Adelie"
                    species_found.append(raw_species.title())
                    break

    all_species_present = all(sp in species_found for sp in expected_species)
    if all_species_present:
        score += 10
        feedback_parts.append("All 3 penguin species present")
    elif len(species_found) >= 2:
        score += 5
        feedback_parts.append(f"Only {len(species_found)} species found")
    else:
        feedback_parts.append("FAIL: Missing species")

    # Criterion 9-10: Numeric values validation (20 points)
    if csv_data:
        numeric_ok, numeric_score, species_results = _validate_numeric_values(csv_data)
        details['numeric_validation'] = species_results

        # Scale score to 20 points (from 15 max)
        scaled_score = int(numeric_score * 20 / 15)
        score += scaled_score

        if numeric_ok:
            feedback_parts.append("Numeric values match expected statistics")
            data_values_correct = True
        elif numeric_score > 5:
            feedback_parts.append("Some numeric values match expected ranges")
        else:
            feedback_parts.append("FAIL: Numeric values don't match expected statistics")
    else:
        feedback_parts.append("FAIL: Could not validate numeric values")

    # ================================================================
    # VLM VERIFICATION (optional, for process validation)
    # ================================================================

    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')

    sampled_frames = sample_frames(traj, num_samples=5) if sample_frames else []
    details['vlm_trajectory_frames'] = len(sampled_frames)

    if query_vlm and len(sampled_frames) >= 2:
        process_result = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames)
        details['vlm_process'] = process_result

        if process_result:
            script_writing = process_result.get('script_writing_visible', False)
            dplyr_visible = process_result.get('dplyr_operations_visible', False)

            if script_writing and dplyr_visible:
                feedback_parts.append("VLM: dplyr workflow visible")
            elif script_writing:
                feedback_parts.append("VLM: Code writing visible")

    # ================================================================
    # FINAL SCORING AND PASS/FAIL
    # ================================================================

    # Key criteria: must have EITHER execution verification OR correct data values
    key_criteria_met = execution_verified or data_values_correct
    passed = score >= 60 and key_criteria_met

    if not key_criteria_met and score >= 60:
        feedback_parts.append("FAIL: Neither R execution nor data validation passed")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "output_exists": result.get('output_exists', False),
            "output_created": result.get('output_created', False),
            "output_rows": result.get('output_rows', 0),
            "exact_columns_found": exact_cols_found,
            "all_species_present": all_species_present,
            "code_is_valid": code_is_valid,
            "execution_verified": execution_verified,
            "data_values_correct": data_values_correct
        },
        "details": details
    }
