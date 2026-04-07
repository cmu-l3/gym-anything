#!/usr/bin/env python3
"""Verifier for housing_development_equity task."""

import json
import tempfile
import os
import csv
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try importing VLM tools, but fall back gracefully
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM tools not available.")

def verify_housing_equity(traj, env_info, task_info) -> Dict[str, Any]:
    """Verify the housing development equity analysis.

    Scoring (100 points total):
    - 20 pts: Notebook execution and logic (pandas, qcut, merge, grouping)
    - 25 pts: Zone CSV Output (existence, filtering constraints, correct quartiles)
    - 25 pts: Quartile CSV Output (existence, EXACTLY 4 rows, pct sums to 1.0)
    - 15 pts: Plot PNG exists and is valid size
    - 15 pts: VLM Verification of trajectory (workflow & chart visualization)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # 1. Read task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # ---------------------------------------------------------
    # Notebook Execution Evaluation (20 pts)
    # ---------------------------------------------------------
    nb_score = 0
    if result.get('notebook_exists') and result.get('notebook_modified'):
        nb_score += 5
    
    nb_a = result.get('notebook_analysis', {})
    if nb_a.get('has_pandas') and nb_a.get('has_read_hdf'):
        nb_score += 5
    if nb_a.get('has_merge'):
        nb_score += 5
    if nb_a.get('has_qcut') and nb_a.get('has_groupby'):
        nb_score += 5
    
    score += nb_score
    feedback.append(f"Notebook logic: {nb_score}/20")

    # ---------------------------------------------------------
    # Zone CSV Validation (25 pts)
    # ---------------------------------------------------------
    zone_score = 0
    if result.get('zone_csv_exists') and result.get('zone_csv_created'):
        zone_score += 5
        
        # Copy and analyze the zone CSV
        temp_zone = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/home/ga/urbansim_projects/output/zone_development_equity.csv", temp_zone.name)
            with open(temp_zone.name, 'r') as f:
                reader = csv.DictReader(f)
                zone_rows = list(reader)
            
            if len(zone_rows) > 0:
                cols = [c.lower().strip() for c in reader.fieldnames or []]
                req_cols = ['total_units', 'recent_units', 'median_income', 'household_count', 'income_quartile']
                
                if all(any(req in c for c in cols) for req in req_cols):
                    zone_score += 5
                
                # Verify filtering constraints
                min_units = min([float(r.get('total_units', r.get('total_units ', 0))) for r in zone_rows] or [0])
                min_hh = min([float(r.get('household_count', r.get('household_count ', 0))) for r in zone_rows] or [0])
                
                if min_units >= 50 and min_hh >= 20:
                    zone_score += 10
                
                # Check that quartile 4 has higher mean income than quartile 1
                try:
                    q1_incomes = [float(r['median_income']) for r in zone_rows if str(r['income_quartile']).strip() == '1']
                    q4_incomes = [float(r['median_income']) for r in zone_rows if str(r['income_quartile']).strip() == '4']
                    if len(q1_incomes) > 0 and len(q4_incomes) > 0:
                        q1_mean = sum(q1_incomes) / len(q1_incomes)
                        q4_mean = sum(q4_incomes) / len(q4_incomes)
                        if q4_mean > q1_mean:
                            zone_score += 5
                except (KeyError, ValueError):
                    pass
        except Exception as e:
            feedback.append(f"Zone CSV error: {e}")
        finally:
            if os.path.exists(temp_zone.name):
                os.unlink(temp_zone.name)
    
    score += zone_score
    feedback.append(f"Zone CSV: {zone_score}/25")

    # ---------------------------------------------------------
    # Quartile CSV Validation (25 pts)
    # ---------------------------------------------------------
    quartile_score = 0
    if result.get('quartile_csv_exists') and result.get('quartile_csv_created'):
        quartile_score += 5
        
        # Copy and analyze the quartile CSV
        temp_quartile = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/home/ga/urbansim_projects/output/quartile_absorption.csv", temp_quartile.name)
            with open(temp_quartile.name, 'r') as f:
                reader = csv.DictReader(f)
                quart_rows = list(reader)
            
            if len(quart_rows) == 4:  # Exactly 4 quartiles
                quartile_score += 10
                
                # Verify percentage sums to ~1.0 or ~100
                pct_key = next((k for k in reader.fieldnames if 'pct' in k.lower()), None)
                if pct_key:
                    try:
                        pct_sum = sum([float(r[pct_key]) for r in quart_rows])
                        # Accept either 1.0 format or 100.0 format
                        if 0.95 <= pct_sum <= 1.05 or 95.0 <= pct_sum <= 105.0:
                            quartile_score += 10
                    except ValueError:
                        pass
        except Exception as e:
            feedback.append(f"Quartile CSV error: {e}")
        finally:
            if os.path.exists(temp_quartile.name):
                os.unlink(temp_quartile.name)

    score += quartile_score
    feedback.append(f"Quartile CSV: {quartile_score}/25")

    # ---------------------------------------------------------
    # Plot Generation (15 pts)
    # ---------------------------------------------------------
    plot_score = 0
    if result.get('plot_exists') and result.get('plot_created'):
        plot_score += 10
        if result.get('plot_size_kb', 0) > 5:
            plot_score += 5
    
    score += plot_score
    feedback.append(f"Plot generation: {plot_score}/15")

    # ---------------------------------------------------------
    # VLM Trajectory Verification (15 pts)
    # ---------------------------------------------------------
    vlm_score = 0
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            prompt = """Analyze this sequence of screenshots from an agent working in Jupyter Lab.
            Determine if the agent successfully analyzed data and created a bar chart.
            
            Check for:
            1. 'notebook_active': Is Jupyter Lab open and showing Python code?
            2. 'chart_plotted': Does any frame (especially the final one) show a rendered bar chart?
            
            Return JSON:
            {"notebook_active": true/false, "chart_plotted": true/false}"""
            
            vlm_res = query_vlm(images=frames + [final_frame], prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('notebook_active'): vlm_score += 5
                if parsed.get('chart_plotted'): vlm_score += 10
            else:
                feedback.append("VLM query failed, relying on programmatic plot check.")
                # Give points if the programmatic check was perfect and VLM failed
                if plot_score == 15: vlm_score = 15
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            if plot_score == 15: vlm_score = 15
    else:
        # If VLM is not available, default to trusting the programmatic plot file check
        if plot_score == 15:
            vlm_score = 15
            
    score += vlm_score
    feedback.append(f"VLM/Visuals: {vlm_score}/15")

    # ---------------------------------------------------------
    # Final Evaluation
    # ---------------------------------------------------------
    passed = score >= 60 and zone_score >= 10 and quartile_score >= 10
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }