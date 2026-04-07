#!/usr/bin/env python3
"""
Verifier for EV Charging Allocation task.

Verification Strategy:
1. Validates task execution state and notebook code patterns (anti-gaming).
2. Uses copy_from_env to extract the generated CSV and verify data correctness:
   - Contains exact columns
   - Exactly 20 rows
   - Mathematically consistent percentages
   - Sorted correctly descending
3. Validates plot existence and size.
4. Uses VLM on trajectory frames to visually verify plot creation in browser.
"""

import json
import tempfile
import os
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ev_charging_allocation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_path = metadata.get('expected_csv_path', '/home/ga/urbansim_projects/output/ev_charging_priority_zones.csv')
    expected_cols = [c.lower() for c in metadata.get('expected_csv_columns', ['zone_id', 'total_households', 'vuln_households', 'vuln_pct'])]
    
    score = 0
    feedback = []
    
    # =======================================================
    # 1. Evaluate Notebook Execution & State (35 points)
    # =======================================================
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read task state result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result:
        return {"passed": False, "score": 0, "feedback": "Failed to load task result JSON."}

    # Base notebook execution (15 points)
    nb_a = result.get('notebook_analysis', {})
    if result.get('notebook_exists') and result.get('notebook_modified_during_task'):
        if nb_a.get('num_executed_cells', 0) > 0 and not nb_a.get('has_errors'):
            score += 15
            feedback.append("Notebook executed successfully.")
        else:
            score += 5
            feedback.append("Notebook exists but has errors or unexecuted cells.")
    else:
        feedback.append("Notebook not found or not modified during task.")

    # Code Logic Patterns (20 points)
    code_score = 0
    if nb_a.get('has_read_hdf'): code_score += 4
    if nb_a.get('has_joins'): code_score += 4
    if nb_a.get('has_groupby'): code_score += 4
    if nb_a.get('has_threshold_logic'): code_score += 4
    if nb_a.get('has_households_filter'): code_score += 4
    score += code_score
    feedback.append(f"Code pattern score: {code_score}/20.")

    # =======================================================
    # 2. Evaluate CSV Outputs (40 points)
    # =======================================================
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    csv_valid = False
    try:
        copy_from_env(expected_csv_path, temp_csv.name)
        if os.path.getsize(temp_csv.name) > 0 and result.get('csv_modified_during_task'):
            csv_valid = True
    except Exception:
        pass

    if csv_valid:
        try:
            with open(temp_csv.name, 'r', encoding='utf-8-sig') as f:
                reader = csv.DictReader(f)
                headers = [h.strip().lower() for h in reader.fieldnames or []]
                rows = list(reader)
                
            # Check columns (10 points)
            has_expected_cols = all(c in headers for c in expected_cols)
            if has_expected_cols:
                score += 10
                feedback.append("CSV has exact expected columns.")
            else:
                feedback.append(f"CSV missing expected columns. Found: {headers}")

            # Check row count (10 points)
            if len(rows) == 20:
                score += 10
                feedback.append("CSV has exactly 20 priority zones.")
            elif len(rows) > 0:
                score += 5
                feedback.append(f"CSV has {len(rows)} rows, expected 20.")
            else:
                feedback.append("CSV is empty.")

            # Check math logic and sorting (20 points)
            if len(rows) > 0 and has_expected_cols:
                math_correct = True
                sorting_correct = True
                prev_pct = float('inf')
                
                # Dynamic matching for column keys
                z_col = next(c for c in headers if 'zone_id' in c)
                th_col = next(c for c in headers if 'total' in c)
                vh_col = next(c for c in headers if 'vuln' in c and 'pct' not in c)
                pct_col = next(c for c in headers if 'pct' in c)

                for r in rows:
                    try:
                        th = float(r[th_col])
                        vh = float(r[vh_col])
                        pct = float(r[pct_col])
                        
                        # Validate calculation (allow small floating point rounding diffs)
                        if th == 0 or abs((vh / th) - pct) > 0.05:
                            math_correct = False
                            
                        # Validate >= 100 filter
                        if th < 100:
                            math_correct = False
                            
                        # Validate descending sort
                        if pct > prev_pct + 0.01:
                            sorting_correct = False
                        prev_pct = pct
                        
                    except (ValueError, ZeroDivisionError):
                        math_correct = False
                        sorting_correct = False
                        break

                if math_correct:
                    score += 10
                    feedback.append("CSV data math/filters are correct.")
                else:
                    feedback.append("CSV math logic incorrect (vuln_pct calculation or <100 filter).")
                    
                if sorting_correct:
                    score += 10
                    feedback.append("CSV data is correctly sorted descending by pct.")
                else:
                    feedback.append("CSV data is not sorted descending.")

        except Exception as e:
            feedback.append(f"Failed to parse CSV data: {e}")
    else:
        feedback.append("Expected CSV file not found or not created during task.")

    if os.path.exists(temp_csv.name):
        os.unlink(temp_csv.name)

    # =======================================================
    # 3. Evaluate Scatter Plot Output (15 points)
    # =======================================================
    if result.get('plot_exists') and result.get('plot_modified_during_task'):
        size_bytes = result.get('plot_size_bytes', 0)
        if size_bytes > 15000:  # > 15KB indicates actual content
            score += 15
            feedback.append("Scatter plot generated and sized reasonably.")
        elif size_bytes > 0:
            score += 5
            feedback.append("Scatter plot generated but suspiciously small.")
        else:
            feedback.append("Scatter plot is empty.")
    else:
        feedback.append("Scatter plot not found or not created during task.")

    # =======================================================
    # 4. VLM Trajectory Verification (10 points)
    # =======================================================
    from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
    
    try:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images_to_check = frames + [final] if final else frames
        
        prompt = """You are evaluating a Jupyter Notebook data science workflow.
        Look through these screenshots and verify:
        Is there a visible scatter plot visualization (dots/points on an X-Y axis) rendered inside the notebook?
        Respond with valid JSON:
        {"has_scatter_plot": true/false}
        """
        
        vlm_resp = query_vlm(prompt=prompt, images=images_to_check)
        if vlm_resp and vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("has_scatter_plot", False):
                score += 10
                feedback.append("VLM verified scatter plot visible in notebook.")
            else:
                feedback.append("VLM did not detect a scatter plot in trajectory.")
    except Exception as e:
        logger.warning(f"VLM trajectory check failed or unavailable: {e}")
        # Soft-fail VLM if unavailable, but don't deduct points unnecessarily if programmatic was perfect
        pass

    passed = score >= 70 and csv_valid
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }