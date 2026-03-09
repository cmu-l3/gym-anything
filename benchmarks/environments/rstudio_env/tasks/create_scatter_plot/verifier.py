#!/usr/bin/env python3
"""
Verifier for create_scatter_plot task.

Verification Strategy (Hybrid: Programmatic + R Execution + VLM):

Programmatic checks (40 points) - from export script JSON:
  1. Output PNG file exists and is valid (10 pts)
  2. Output was created during task (5 pts)
  3. Output file size is reasonable (5 pts)
  4. Script was modified during task (5 pts)
  5. Script contains actual R code, not just comments (15 pts)

R Execution verification (30 points) - actually run the script:
  6. R script executes without syntax errors (15 pts)
  7. R script produces the expected output file when run fresh (15 pts)

VLM visual verification (30 points) - verify plot content:
  8. Trajectory shows RStudio workflow progression (10 pts)
  9. Final plot is a valid scatter plot (10 pts)
  10. Plot shows correct data pattern (flipper vs mass relationship) (10 pts)

Adversarial detection:
  - Reject scripts that are only comments
  - Reject pre-existing or downloaded images
  - Verify R code actually produces the output
  - Cross-validate programmatic results with VLM

Pass threshold: 60 points AND (R execution success OR VLM verification pass)
"""

import json
import tempfile
import os
import re
import logging
import hashlib

logger = logging.getLogger(__name__)


# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_PROCESS_PROMPT = """You are analyzing screenshots from an agent creating a scatter plot in RStudio.

The images show the agent's progression through the task. Look for evidence of:
1. RStudio open with an R script file
2. R code being written (not just comments)
3. Script execution (console output, plot appearing)
4. Final plot visible in the Plots pane or as a saved file

Assess:
- SCRIPT_WRITING: Did the agent actually write R code (not just navigate menus)?
- CODE_EXECUTION: Is there evidence the code was run (console output, plot visible)?
- MEANINGFUL_WORK: Do frames show real coding activity (not same screen repeated)?

Respond in JSON format:
{
    "script_writing_visible": true/false,
    "code_execution_visible": true/false,
    "meaningful_work": true/false,
    "stages_observed": ["list what you see"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe the workflow you see"
}
"""

SCATTER_PLOT_VERIFICATION_PROMPT = """You are analyzing a scatter plot image to verify it meets task requirements.

The task required creating a scatter plot of Palmer Penguins data with:
- X-axis: flipper length (in mm, values roughly 170-230)
- Y-axis: body mass (in grams, values roughly 2700-6300)
- ~340 data points showing 3 species clusters

Analyze this plot image and assess:

1. IS_SCATTER_PLOT: Is this actually a scatter plot (individual data points)?
   Not a line plot, bar chart, histogram, or blank image.

2. CORRECT_AXES: Do the axes appear to show:
   - X-axis with values in the 170-230 range (flipper length)
   - Y-axis with values in the 2700-6300 range (body mass)

3. DATA_PATTERN: Does the plot show:
   - Multiple data points (should be 300+)
   - A positive correlation pattern (larger flippers = heavier penguins)
   - Possibly distinct clusters (3 species)

4. NOT_PLACEHOLDER: Is this a real data plot, not:
   - A stock image or placeholder
   - An example plot from documentation
   - A completely random scatter pattern

Respond in JSON format:
{
    "is_scatter_plot": true/false,
    "correct_axes_visible": true/false,
    "axes_labels_appropriate": true/false,
    "data_pattern_correct": true/false,
    "approximate_point_count": "few (<50)", "moderate (50-200)", "many (200+)",
    "positive_correlation_visible": true/false,
    "not_placeholder": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see in the plot"
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
    Check if script contains actual R code, not just comments or keywords in strings.
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
    has_ggplot_call = any(re.search(r'ggplot\s*\(', line) for line in code_lines)
    # Accept multiple save methods: ggsave(), png()+dev.off(), pdf()+dev.off()
    has_ggsave = any(re.search(r'ggsave\s*\(', line) for line in code_lines)
    has_png_device = any(re.search(r'png\s*\(', line) for line in code_lines)
    has_pdf_device = any(re.search(r'pdf\s*\(', line) for line in code_lines)
    has_dev_off = any(re.search(r'dev\.off\s*\(', line) for line in code_lines)
    has_save_call = has_ggsave or (has_png_device and has_dev_off) or (has_pdf_device and has_dev_off)
    has_assignment = any(re.search(r'<-|=(?!=)', line) for line in code_lines)

    if not (has_read_data or has_assignment):
        return False, len(code_lines), "No data loading or assignments found"

    if not has_ggplot_call:
        return False, len(code_lines), "No ggplot() function call found"

    if not has_save_call:
        return False, len(code_lines), "No plot save function found (need ggsave or png+dev.off)"

    return True, len(code_lines), "Valid R code structure"


def _compute_file_hash(filepath):
    """Compute SHA256 hash of a file."""
    try:
        with open(filepath, 'rb') as f:
            return hashlib.sha256(f.read()).hexdigest()
    except Exception:
        return None


# ================================================================
# MAIN VERIFIER
# ================================================================

def verify_scatter_plot(traj, env_info, task_info):
    """
    Verify scatter plot creation with robust anti-gaming checks.

    Scoring (100 points total):
    - Programmatic (40 pts): file checks, script validation
    - R Execution (30 pts): script actually runs and produces output
    - VLM (30 pts): visual verification of plot content

    Pass threshold: 60 points AND (execution_verified OR vlm_verified)
    """
    copy_from_env = env_info.get('copy_from_env')
    run_in_env = env_info.get('run_in_env')  # For R execution

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_size_kb = metadata.get('min_plot_size_kb', 10)

    feedback_parts = []
    score = 0
    details = {}

    # Flags for key criteria
    execution_verified = False
    vlm_verified = False
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
        copy_from_env("/home/ga/RProjects/analysis.R", script_temp.name)
        with open(script_temp.name, 'r') as f:
            script_content = f.read()
    except Exception:
        pass
    finally:
        if os.path.exists(script_temp.name):
            os.unlink(script_temp.name)

    details['script_length'] = len(script_content)

    # ================================================================
    # PROGRAMMATIC CHECKS (40 points)
    # ================================================================

    # Criterion 1: Output file exists and is valid PNG (10 points)
    png_valid = False
    png_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    png_hash = None
    try:
        copy_from_env("/home/ga/RProjects/output/penguin_scatter.png", png_temp.name)
        with open(png_temp.name, 'rb') as f:
            header = f.read(8)
            if header[:8] == b'\x89PNG\r\n\x1a\n':
                png_valid = True
                png_hash = _compute_file_hash(png_temp.name)
    except Exception:
        pass
    finally:
        if os.path.exists(png_temp.name):
            os.unlink(png_temp.name)

    if result.get('output_exists') and png_valid:
        score += 10
        feedback_parts.append("PNG file exists and is valid")
        details['png_valid'] = True
    elif result.get('output_exists'):
        score += 3
        feedback_parts.append("Output file exists but may not be valid PNG")
        details['png_valid'] = False
    else:
        feedback_parts.append("FAIL: Output PNG not found")
        details['png_valid'] = False

    # Criterion 2: Output was created during task (5 points)
    if result.get('output_created') or result.get('output_modified'):
        score += 5
        feedback_parts.append("Output created during task")
    else:
        feedback_parts.append("FAIL: Output not created during task")

    # Criterion 3: File size reasonable (5 points)
    output_size = result.get('output_size_kb', 0)
    if output_size >= min_size_kb:
        score += 5
        feedback_parts.append(f"Output size OK ({output_size}KB)")
    elif output_size > 0:
        score += 2
        feedback_parts.append(f"Output size small ({output_size}KB)")
    else:
        feedback_parts.append("FAIL: Output empty")

    # Criterion 4: Script was modified (5 points)
    if result.get('script_modified'):
        score += 5
        feedback_parts.append("Script was modified")
    else:
        feedback_parts.append("FAIL: Script not modified")

    # Criterion 5: Script contains actual R code (15 points)
    # This is the ADVERSARIAL CHECK - reject scripts that are just comments
    code_valid, code_lines, code_reason = _is_valid_r_code(script_content)
    details['code_validation'] = {'valid': code_valid, 'lines': code_lines, 'reason': code_reason}

    if code_valid:
        score += 15
        feedback_parts.append(f"Valid R code ({code_lines} lines)")
        code_is_valid = True
    elif code_lines > 0:
        score += 5
        feedback_parts.append(f"Incomplete R code: {code_reason}")
    else:
        feedback_parts.append(f"FAIL: Invalid R code - {code_reason}")

    # ================================================================
    # R EXECUTION VERIFICATION (30 points)
    #
    # This is the KEY ANTI-GAMING CHECK: actually run the R script
    # and verify it produces the expected output.
    # ================================================================

    if run_in_env and code_is_valid:
        # Remove existing output first
        try:
            run_in_env("rm -f /home/ga/RProjects/output/penguin_scatter_test.png")
        except Exception:
            pass

        # Create a test script that sources the user's script
        # Intercepts both ggsave() and png()/dev.off() patterns
        test_script = """
# Test execution of user's scatter plot script
tryCatch({
    # Intercept ggsave to redirect output
    original_ggsave <- ggsave
    ggsave <- function(filename, ...) {
        if (grepl("penguin_scatter", filename)) {
            filename <- "/home/ga/RProjects/output/penguin_scatter_test.png"
        }
        original_ggsave(filename, ...)
    }

    # Intercept png() device to redirect output
    original_png <- png
    png <- function(filename, ...) {
        if (grepl("penguin_scatter", filename)) {
            filename <- "/home/ga/RProjects/output/penguin_scatter_test.png"
        }
        original_png(filename, ...)
    }

    # Intercept pdf() device as well
    original_pdf <- pdf
    pdf <- function(file, ...) {
        if (grepl("penguin_scatter", file)) {
            file <- "/home/ga/RProjects/output/penguin_scatter_test.pdf"
        }
        original_pdf(file, ...)
    }

    # Source the user's script
    source("/home/ga/RProjects/analysis.R")

    cat("EXECUTION_SUCCESS\\n")
}, error = function(e) {
    cat(paste("EXECUTION_ERROR:", conditionMessage(e), "\\n"))
})
"""

        try:
            # Write and run test script
            run_in_env(f"cat > /tmp/test_scatter.R << 'TESTEOF'\n{test_script}\nTESTEOF")
            exec_result = run_in_env("cd /home/ga/RProjects && Rscript /tmp/test_scatter.R 2>&1")

            if exec_result and "EXECUTION_SUCCESS" in exec_result:
                # Check if output was created
                test_output_check = run_in_env("ls -la /home/ga/RProjects/output/penguin_scatter_test.png 2>&1")

                if test_output_check and "No such file" not in test_output_check:
                    score += 30
                    feedback_parts.append("R execution verified: script runs and produces output")
                    execution_verified = True
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
        feedback_parts.append("R execution check skipped (no run capability or invalid code)")

    # ================================================================
    # VLM VISUAL VERIFICATION (30 points)
    # ================================================================

    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')

    sampled_frames = sample_frames(traj, num_samples=5) if sample_frames else []
    final_frame = get_final(traj) if get_final else None

    details['vlm_trajectory_frames'] = len(sampled_frames)
    details['vlm_has_final_frame'] = final_frame is not None

    if query_vlm:
        # VLM Check A: Trajectory Process Verification (10 points)
        if len(sampled_frames) >= 2:
            process_result = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames)
            details['vlm_process'] = process_result

            if process_result:
                script_writing = process_result.get('script_writing_visible', False)
                code_execution = process_result.get('code_execution_visible', False)
                meaningful_work = process_result.get('meaningful_work', False)

                if script_writing and code_execution and meaningful_work:
                    score += 10
                    feedback_parts.append("VLM: Full workflow verified")
                elif script_writing and (code_execution or meaningful_work):
                    score += 7
                    feedback_parts.append("VLM: Partial workflow verified")
                elif meaningful_work:
                    score += 4
                    feedback_parts.append("VLM: Some activity visible")
                else:
                    feedback_parts.append("VLM: Workflow not confirmed")
            else:
                feedback_parts.append("VLM process check failed")
        else:
            feedback_parts.append("VLM process: Insufficient frames")

        # VLM Check B: Plot Content Verification (20 points)
        # Try to use the actual PNG file, or fall back to final screenshot
        plot_image = None

        # First try to copy the actual output PNG
        plot_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/home/ga/RProjects/output/penguin_scatter.png", plot_temp.name)
            if os.path.getsize(plot_temp.name) > 1000:  # At least 1KB
                plot_image = plot_temp.name
        except Exception:
            pass

        if not plot_image and final_frame:
            plot_image = final_frame

        if plot_image:
            content_result = _vlm_query(query_vlm, SCATTER_PLOT_VERIFICATION_PROMPT, image=plot_image)
            details['vlm_content'] = content_result

            if content_result:
                is_scatter = content_result.get('is_scatter_plot', False)
                correct_axes = content_result.get('correct_axes_visible', False)
                data_pattern = content_result.get('data_pattern_correct', False)
                not_placeholder = content_result.get('not_placeholder', False)
                point_count = content_result.get('approximate_point_count', 'unknown')

                # Score based on visual verification
                if is_scatter and not_placeholder:
                    score += 10
                    feedback_parts.append("VLM: Valid scatter plot confirmed")

                    if correct_axes and data_pattern:
                        score += 10
                        feedback_parts.append("VLM: Correct data pattern (flipper vs mass)")
                        vlm_verified = True
                    elif correct_axes or data_pattern:
                        score += 5
                        feedback_parts.append("VLM: Partial data verification")
                    else:
                        feedback_parts.append("VLM: Plot content unclear")
                elif is_scatter:
                    score += 5
                    feedback_parts.append("VLM: Scatter plot detected but may be placeholder")
                else:
                    feedback_parts.append("VLM: Not a valid scatter plot")
            else:
                feedback_parts.append("VLM content check failed")
        else:
            feedback_parts.append("VLM content: No plot image available")

        # Clean up temp file
        if plot_image and plot_image != final_frame:
            try:
                os.unlink(plot_image)
            except Exception:
                pass
    else:
        feedback_parts.append("VLM verification not available")

    # ================================================================
    # FINAL SCORING AND PASS/FAIL
    # ================================================================

    # Key criteria: must have EITHER execution verification OR VLM verification
    # This prevents gaming by either:
    # - Creating fake files (caught by execution check)
    # - Writing non-functional code (caught by VLM showing no real plot)

    key_criteria_met = execution_verified or vlm_verified
    passed = score >= 60 and key_criteria_met

    if not key_criteria_met and score >= 60:
        feedback_parts.append("FAIL: Neither R execution nor VLM verification passed")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "output_exists": result.get('output_exists', False),
            "output_created": result.get('output_created', False),
            "output_size_kb": result.get('output_size_kb', 0),
            "png_valid": png_valid,
            "script_modified": result.get('script_modified', False),
            "code_is_valid": code_is_valid,
            "execution_verified": execution_verified,
            "vlm_verified": vlm_verified
        },
        "details": details
    }
