#!/usr/bin/env python3
"""Verifier for transit_corridor_catchment_analysis task."""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_transit_corridor(traj, env_info, task_info):
    """Verify transit corridor analysis outputs against ground truth calculations."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # 1. Retrieve the Task Result JSON
    task_res = None
    temp_tr = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_tr.name)
        with open(temp_tr.name, 'r') as f:
            task_res = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(temp_tr.name):
            os.unlink(temp_tr.name)

    if task_res is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # Notebook Basics (10 points)
    if task_res.get('notebook_exists') and task_res.get('notebook_modified'):
        score += 5
    if task_res.get('notebook_analysis', {}).get('num_executed_cells', 0) >= 1:
        score += 5
        feedback.append("Notebook executed.")
    else:
        feedback.append("Notebook not executed.")

    # 2. Retrieve Ground Truth JSON
    gt = None
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ground_truth_catchment.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load GT: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    if not gt or "error" in gt:
        return {"passed": False, "score": 0, "feedback": "Verifier Error: Missing or invalid Ground Truth"}

    # 3. Retrieve Agent JSON Output
    agent_json = None
    if task_res.get('json_exists'):
        temp_aj = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/home/ga/urbansim_projects/output/catchment_metrics.json", temp_aj.name)
            with open(temp_aj.name, 'r') as f:
                agent_json = json.load(f)
        except Exception as e:
            feedback.append("Failed to parse agent's catchment_metrics.json (invalid JSON).")
        finally:
            if os.path.exists(temp_aj.name):
                os.unlink(temp_aj.name)
    else:
        feedback.append("Agent output JSON missing.")

    # Tolerances
    GEOMETRY_TOL = 0.001  # 0.1% tolerance
    METRICS_TOL = 0.01    # 1% tolerance

    def close_enough(val_a, val_b, tol):
        if val_b == 0:
            return abs(val_a) < 1e-5
        return abs(val_a - val_b) / abs(val_b) <= tol

    # Evaluate Agent JSON Geometry (20 pts) & Metrics (50 pts)
    if agent_json:
        try:
            # Geometry check
            gt_corridor = gt["corridor"]
            ag_corridor = agent_json["corridor"]
            geom_passed = True
            
            for pt in ["p_west", "p_east"]:
                for ax in ["x", "y"]:
                    if not close_enough(ag_corridor[pt][ax], gt_corridor[pt][ax], GEOMETRY_TOL):
                        geom_passed = False
            
            if not close_enough(agent_json["buffer_distance"], gt["buffer_distance"], GEOMETRY_TOL):
                geom_passed = False
                
            if geom_passed:
                score += 20
                feedback.append("Geometry matches ground truth (20/20)")
            else:
                feedback.append("Geometry/Buffer differs from ground truth (0/20)")

            # Metrics checks (Citywide: 15 pts, Catchment: 25 pts, Shares: 10 pts)
            gt_met = gt["metrics"]
            ag_met = agent_json["metrics"]
            
            cats = ["parcels", "res_units", "households", "population", "jobs"]
            cw_hits = 0
            ca_hits = 0
            sh_hits = 0

            for c in cats:
                # Check Citywide
                if close_enough(ag_met[c]["citywide"], gt_met[c]["citywide"], METRICS_TOL):
                    cw_hits += 1
                # Check Catchment
                if close_enough(ag_met[c]["catchment"], gt_met[c]["catchment"], METRICS_TOL):
                    ca_hits += 1
                # Check Share Pct
                if close_enough(ag_met[c]["share_pct"], gt_met[c]["share_pct"], METRICS_TOL):
                    sh_hits += 1

            cw_score = (cw_hits / 5.0) * 15
            ca_score = (ca_hits / 5.0) * 25
            sh_score = (sh_hits / 5.0) * 10
            
            score += cw_score + ca_score + sh_score
            feedback.append(f"Metrics accuracy: Citywide ({cw_score:.1f}/15), Catchment ({ca_score:.1f}/25), Shares ({sh_score:.1f}/10)")

        except KeyError as e:
            feedback.append(f"Agent JSON missing required key: {e}")
        except Exception as e:
            feedback.append(f"Error validating agent JSON structure: {e}")

    # Plot Verification (10 points)
    if task_res.get('plot_exists'):
        if task_res.get('plot_size_kb', 0) > 10:
            score += 10
            feedback.append("Map generated successfully (10/10)")
        else:
            score += 5
            feedback.append("Map generated but unusually small (5/10)")
    else:
        feedback.append("Map not found (0/10)")

    # Anti-gaming: Ensure modified dates are after task start
    if agent_json and not task_res.get('json_created'):
        score = min(score, 10)
        feedback.append("Warning: JSON was not created during the task timeframe.")

    passed = score >= 75
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }