#!/usr/bin/env python3
"""
Verifier for Monte Carlo Uncertainty Quantification task.

The agent must:
1. Import USLCI database and LCIA methods
2. Find coal electricity generation in USLCI and build a product system
3. Define >= 3 parameters with uncertainty distributions
4. Run Monte Carlo simulation (500+ iterations) for GWP
5. Export uncertainty statistics (mean, std, 95% CI) to CSV

Scoring (100 points total):
  Programmatic:
    - (15 pts) Database imported (> 15MB)
    - (10 pts) LCIA methods imported (impact_cat_count > 0)
    - (20 pts) Product system created (ps_count >= 1)
    - (20 pts) Parameters with uncertainty defined (param_count >= 3)
    - (20 pts) Monte Carlo result file exported (size > 100 bytes)
    - (15 pts) File content has statistical output (mean, std, confidence)
  VLM:
    - (5 pts)  Trajectory shows Monte Carlo workflow
    - (5 pts)  Final state shows MC results or exported file

Pass threshold: 60 points.
GATE: If no product system AND no result file → score capped at 30.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TRAJECTORY_PROMPT = """You are reviewing screenshots of an agent using openLCA to run a Monte Carlo uncertainty simulation for coal electricity LCA.

The expected workflow includes:
1. Importing a database (USLCI) and LCIA methods
2. Finding a coal electricity process and creating a product system
3. Opening parameter editor and defining parameters with uncertainty distributions (normal, log-normal)
4. Opening the Calculation dialog and selecting 'Monte Carlo Simulation' as the calculation type
5. Configuring number of iterations (500+) and running the simulation
6. Viewing Monte Carlo statistics results (mean, std dev, confidence intervals)
7. Exporting results to a CSV file

Assess:
- PRODUCT_SYSTEM_CREATED: Evidence of a product system being created
- PARAMETER_SETUP: Evidence of parameters/uncertainty being configured
- MONTE_CARLO_RUN: Evidence of Monte Carlo dialog or simulation running
- STATISTICS_VISIBLE: Uncertainty statistics (mean, std, CI) visible on screen
- EXPORT_DONE: Evidence of result export

Return JSON:
{
  "product_system_created": true/false,
  "parameter_setup": true/false,
  "monte_carlo_run": true/false,
  "statistics_visible": true/false,
  "export_done": true/false,
  "confidence": "low"/"medium"/"high",
  "observations": "brief description"
}"""

FINAL_FRAME_PROMPT = """This is the final screenshot from an agent performing Monte Carlo uncertainty analysis in openLCA for coal electricity GWP.

A successful final state could show:
- A Monte Carlo results table/dialog with statistics (mean, standard deviation, min, max, percentiles)
- A CSV file open in a text editor or spreadsheet showing uncertainty statistics
- openLCA results view with confidence interval data visible
- A bar chart or histogram from the Monte Carlo simulation

Check:
- MC_RESULTS_VISIBLE: Are Monte Carlo/uncertainty statistics visible?
- STATISTICS_SHOWN: Can you see statistical values (mean, std dev, confidence intervals)?
- GWP_CONTEXT: Is global warming potential or CO2 the focus?
- TASK_COMPLETE: Does the state look like the simulation is done and results exported?

Return JSON:
{
  "mc_results_visible": true/false,
  "statistics_shown": true/false,
  "gwp_context": true/false,
  "task_complete": true/false,
  "confidence": "low"/"medium"/"high",
  "observations": "description of what you see"
}"""


def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None


def verify_monte_carlo_uncertainty(traj, env_info, task_info):
    """Verify Monte Carlo uncertainty analysis was performed."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []
    subscores = {}

    # ── Criterion 1: Database imported (15 pts) ────────────────────────────────
    db_ok = result.get('db_found') and result.get('db_size_mb', 0) > 15
    if db_ok:
        score += 15
        subscores['database'] = True
        feedback.append(f"Database imported ({result.get('db_size_mb')}MB)")
    else:
        subscores['database'] = False
        feedback.append("Database not imported or too small")

    # ── Criterion 2: LCIA methods imported (10 pts) ───────────────────────────
    lcia_ok = result.get('impact_cat_count', 0) > 0
    if lcia_ok:
        score += 10
        subscores['lcia'] = True
        feedback.append(f"LCIA methods imported ({result.get('impact_cat_count')} categories)")
    else:
        subscores['lcia'] = False
        feedback.append("LCIA methods not imported")

    # ── Criterion 3: Product system created (20 pts) ──────────────────────────
    ps_count = result.get('ps_count', 0)
    if ps_count >= 1:
        score += 20
        subscores['product_system'] = True
        feedback.append(f"Product system created (ps_count={ps_count})")
    else:
        subscores['product_system'] = False
        feedback.append("No product system found in database")

    # ── Criterion 4: Parameters with uncertainty defined (20 pts) ─────────────
    param_count = result.get('param_count', 0)
    if param_count >= 3:
        score += 20
        subscores['parameters'] = True
        feedback.append(f"Parameters defined with uncertainty: {param_count} (>= 3 required)")
    elif param_count >= 1:
        score += 8
        subscores['parameters'] = False
        feedback.append(f"Only {param_count} parameter(s) defined — need at least 3")
    else:
        subscores['parameters'] = False
        # Check log/window for evidence that Monte Carlo was at least attempted
        if result.get('mc_window_visible') or result.get('mc_in_log'):
            score += 5
            feedback.append("Monte Carlo attempted but no persistent parameters found")
        else:
            feedback.append("No parameters defined and no Monte Carlo evidence")

    # ── Criterion 5: Monte Carlo result file exported (20 pts) ────────────────
    has_file = (
        result.get('mc_file') and
        result.get('mc_file_size', 0) > 100
    )
    if has_file:
        score += 20
        subscores['mc_file'] = True
        feedback.append(
            f"MC result file exported ({result.get('mc_file_size')} bytes): "
            f"{os.path.basename(result.get('mc_file', ''))}"
        )
    elif result.get('current_result_count', 0) > result.get('initial_result_count', 0):
        score += 8
        subscores['mc_file'] = False
        feedback.append("New file in results directory but not recognized as MC output")
    else:
        subscores['mc_file'] = False
        feedback.append("No Monte Carlo result file exported")

    # ── Criterion 6: Statistical content in file (15 pts) ─────────────────────
    has_mean = result.get('has_mean_keyword', 0) == 1
    has_std = result.get('has_std_keyword', 0) == 1
    has_ci = result.get('has_confidence_keyword', 0) == 1
    has_gwp = result.get('has_gwp_keyword', 0) == 1

    stat_score = 0
    stat_parts = []
    if has_mean:
        stat_score += 4
        stat_parts.append("mean")
    if has_std:
        stat_score += 4
        stat_parts.append("std dev")
    if has_ci:
        stat_score += 4
        stat_parts.append("confidence interval")
    if has_gwp:
        stat_score += 3
        stat_parts.append("GWP values")

    if stat_score > 0:
        score += stat_score
        subscores['statistics_content'] = stat_score >= 8
        feedback.append(f"Statistical content: {', '.join(stat_parts)}")
    else:
        subscores['statistics_content'] = False
        if has_file:
            feedback.append("File found but lacks statistical keywords (mean/std/CI)")

    # ── VLM Checks ────────────────────────────────────────────────────────────
    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')

    sampled = sample_frames(traj, num_samples=6) if sample_frames else []
    final_frame = get_final(traj) if get_final else None
    vlm_ok = query_vlm is not None

    # VLM: trajectory (5 pts)
    if vlm_ok and len(sampled) >= 2:
        traj_result = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=sampled)
        if traj_result:
            traj_pts = 0
            if traj_result.get('monte_carlo_run'):
                traj_pts += 3
            if traj_result.get('parameter_setup'):
                traj_pts += 2
            score += traj_pts
            feedback.append(
                f"VLM trajectory: MC_run={traj_result.get('monte_carlo_run')}, "
                f"params={traj_result.get('parameter_setup')}"
            )
        else:
            feedback.append("VLM trajectory unavailable")
    else:
        feedback.append("VLM trajectory: insufficient data")

    # VLM: final frame (5 pts)
    if vlm_ok and final_frame:
        final_result = _vlm_query(query_vlm, FINAL_FRAME_PROMPT, image=final_frame)
        if final_result:
            final_pts = 0
            if final_result.get('mc_results_visible'):
                final_pts += 3
            if final_result.get('statistics_shown'):
                final_pts += 2
            score += final_pts
            feedback.append(
                f"VLM final: MC_results={final_result.get('mc_results_visible')}, "
                f"statistics={final_result.get('statistics_shown')}"
            )
        else:
            feedback.append("VLM final frame unavailable")
    else:
        feedback.append("VLM final: no frame or unavailable")

    # ── GATE check ────────────────────────────────────────────────────────────
    # Must have product system AND some result to pass
    if score >= 60 and ps_count == 0 and not has_file:
        score = 30
        feedback.append("GATE: No product system and no result file — score capped at 30")

    passed = score >= 60

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "debug": {
            "ps_count": ps_count,
            "param_count": param_count,
            "mc_file_size": result.get('mc_file_size', 0),
            "stat_score": stat_score,
        }
    }
