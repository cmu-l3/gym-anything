#!/usr/bin/env python3
"""
Verifier for longitudinal_seizure_gee task.

Task: Biostatistical analysis of Thall & Vail (1990) epilepsy RCT using
GEE and GLMM models for longitudinal count data.

Scoring (100 points total):
  Subtask 1 - Model comparison CSV (30 pts):
    - CSV exists and is new (10 pts)
    - Has required columns (treatment_RR, p_value) (10 pts)
    - Treatment RR values in biologically plausible range 0.3-2.0 (10 pts)

  Subtask 2 - Diagnostics CSV (25 pts):
    - CSV exists and is new (10 pts)
    - Contains overdispersion metric (8 pts)
    - Overdispersion > 1.0 (correct for this overdispersed dataset) (7 pts)

  Subtask 3 - Multi-panel figure (25 pts):
    - PNG exists and is new (10 pts)
    - File size > 30KB (substantial figure) (10 pts)
    - Valid PNG header (5 pts)

  Subtask 4 - R script quality (20 pts):
    - Script was modified during task (5 pts)
    - Script contains GEE function call (geeglm, gee, geese) (10 pts)
    - Script contains output-writing calls (5 pts)

Pass threshold: 60 points
Wrong-target gate: not applicable (single dataset)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/longitudinal_seizure_gee_result.json"


def verify_longitudinal_seizure_gee(traj, env_info, task_info):
    """
    Verify the epilepsy GEE/GLMM analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load export result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        except FileNotFoundError:
            return {"passed": False, "score": 0,
                    "feedback": "Result file not found — export script may not have run"}
        except json.JSONDecodeError as e:
            return {"passed": False, "score": 0,
                    "feedback": f"Result JSON malformed: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []

    # ----------------------------------------------------------------
    # Subtask 1: Model comparison CSV (30 pts)
    # ----------------------------------------------------------------
    if result.get('model_csv_exists') and result.get('model_csv_is_new'):
        score += 10
        feedback.append("Model CSV created (10/10)")
    elif result.get('model_csv_exists'):
        score += 3
        feedback.append("Model CSV exists but not new — may be pre-existing (3/10)")
    else:
        feedback.append("Model CSV missing (0/10)")

    if result.get('model_has_rr_column') and result.get('model_has_pval_column'):
        score += 10
        feedback.append("Model CSV has required columns: RR and p_value (10/10)")
    elif result.get('model_has_rr_column') or result.get('model_has_pval_column'):
        score += 5
        feedback.append("Model CSV has partial columns (5/10)")
    else:
        feedback.append("Model CSV missing required columns (0/10)")

    if result.get('model_rr_in_range'):
        score += 10
        feedback.append("Treatment RR in biologically plausible range 0.2-3.0 (10/10)")
    else:
        feedback.append("Treatment RR out of range or missing (0/10)")

    # ----------------------------------------------------------------
    # Subtask 2: Diagnostics CSV (25 pts)
    # ----------------------------------------------------------------
    if result.get('diag_csv_exists') and result.get('diag_csv_is_new'):
        score += 10
        feedback.append("Diagnostics CSV created (10/10)")
    elif result.get('diag_csv_exists'):
        score += 3
        feedback.append("Diagnostics CSV exists but not new (3/10)")
    else:
        feedback.append("Diagnostics CSV missing (0/10)")

    if result.get('diag_has_overdispersion'):
        score += 8
        feedback.append("Overdispersion metric present in diagnostics (8/8)")
    else:
        feedback.append("Overdispersion metric not found in diagnostics (0/8)")

    if result.get('diag_overdispersion_gt1'):
        score += 7
        feedback.append("Overdispersion ratio > 1.0 (correct for this dataset) (7/7)")
    else:
        feedback.append("Overdispersion ratio not > 1.0 or missing (0/7)")

    # ----------------------------------------------------------------
    # Subtask 3: Multi-panel figure (25 pts)
    # ----------------------------------------------------------------
    plot_size_kb = result.get('plot_size_kb', 0)

    if result.get('plot_exists') and result.get('plot_is_new'):
        score += 10
        feedback.append("Figure PNG created (10/10)")
    elif result.get('plot_exists'):
        score += 3
        feedback.append("Figure PNG exists but not new (3/10)")
    else:
        feedback.append("Figure PNG missing (0/10)")

    if plot_size_kb >= 30:
        score += 10
        feedback.append(f"Figure size substantial: {plot_size_kb}KB (10/10)")
    elif plot_size_kb >= 10:
        score += 5
        feedback.append(f"Figure small: {plot_size_kb}KB (5/10)")
    else:
        feedback.append(f"Figure too small or empty: {plot_size_kb}KB (0/10)")

    # Validate PNG header
    png_valid = False
    png_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    png_tmp.close()
    try:
        copy_from_env("/home/ga/RProjects/output/seizure_analysis.png", png_tmp.name)
        with open(png_tmp.name, 'rb') as f:
            header = f.read(8)
            if header[:8] == b'\x89PNG\r\n\x1a\n':
                png_valid = True
    except Exception:
        pass
    finally:
        try:
            os.unlink(png_tmp.name)
        except Exception:
            pass

    if png_valid:
        score += 5
        feedback.append("Valid PNG header confirmed (5/5)")
    else:
        feedback.append("PNG header invalid or file missing (0/5)")

    # ----------------------------------------------------------------
    # Subtask 4: R script quality (20 pts)
    # ----------------------------------------------------------------
    if result.get('script_is_new'):
        score += 5
        feedback.append("R script modified during task (5/5)")
    else:
        feedback.append("R script not modified (0/5)")

    if result.get('script_has_gee_call'):
        score += 10
        feedback.append("GEE function call found in script (geeglm/gee/geese) (10/10)")
    else:
        feedback.append("No GEE function call found in script (0/10)")

    if result.get('script_has_output_call'):
        score += 5
        feedback.append("Output-writing calls found in script (5/5)")
    else:
        feedback.append("No output-writing calls in script (0/5)")

    # ----------------------------------------------------------------
    # VLM verification (bonus, up to 10 pts — replaces some programmatic pts if needed)
    # ----------------------------------------------------------------
    query_vlm = env_info.get('query_vlm')
    get_final = env_info.get('get_final_screenshot')
    final_frame = get_final(traj) if get_final else None

    if query_vlm and final_frame and score < 100:
        vlm_prompt = """You are reviewing a final screenshot of RStudio after a biostatistical analysis task.
The agent was asked to analyze longitudinal epilepsy trial data using GEE models.

Assess whether the RStudio environment shows evidence of meaningful statistical analysis:
- Is there R code visible with statistical modeling functions (geeglm, glm, ggplot, etc.)?
- Is there output visible in the Console showing model results or data summaries?
- Is there a plot visible in the Plots pane showing data visualization?

Respond in JSON:
{"analysis_visible": true/false, "output_visible": true/false, "plot_visible": true/false, "confidence": "low/medium/high"}"""
        try:
            vlm_result = query_vlm(prompt=vlm_prompt, image=final_frame)
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if parsed.get('analysis_visible') and parsed.get('output_visible'):
                    bonus = min(10, 100 - score)
                    score += bonus
                    feedback.append(f"VLM: Active analysis workflow visible (+{bonus} pts)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # ----------------------------------------------------------------
    # Score cap gates (Lesson 25): each required deliverable must be present to pass
    # Without gate, an agent producing only 2 of 3 deliverables + script could pass at 75pts
    # ----------------------------------------------------------------
    PASS_THRESHOLD = 60
    diag_present = result.get('diag_csv_exists') and result.get('diag_csv_is_new')
    if not diag_present and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback.append(f"Score capped at {PASS_THRESHOLD - 1}: seizure_diagnostics.csv is a required deliverable")

    # ----------------------------------------------------------------
    # Final scoring
    # ----------------------------------------------------------------
    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "model_csv_created": result.get('model_csv_is_new', False),
            "model_has_columns": result.get('model_has_rr_column', False) and result.get('model_has_pval_column', False),
            "rr_in_range": result.get('model_rr_in_range', False),
            "diag_csv_created": result.get('diag_csv_is_new', False),
            "overdispersion_correct": result.get('diag_overdispersion_gt1', False),
            "plot_created": result.get('plot_is_new', False),
            "script_has_gee": result.get('script_has_gee_call', False),
        }
    }
