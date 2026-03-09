#!/usr/bin/env python3
"""Verifier for run_hedonic_regression task."""

import json
import tempfile
import os
import re


def verify_hedonic_regression(traj, env_info, task_info):
    """Verify hedonic regression model was built successfully.

    Scoring (100 points total):
    - Programmatic checks (40 pts): notebook code, CSV structure, plot file
    - Code analysis (30 pts): deep notebook code verification
    - Output validation + VLM (30 pts): CSV content, plot validity, VLM check
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    # =========================================
    # Part 1: Programmatic checks (40 points)
    # =========================================

    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read task result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    if result.get('notebook_exists') and result.get('notebook_modified'):
        score += 5

    nb_analysis = result.get('notebook_analysis', {})
    nb_code_score = 0
    if nb_analysis.get('has_code'):
        nb_code_score += 2
    if nb_analysis.get('has_pandas'):
        nb_code_score += 2
    if nb_analysis.get('has_hdf'):
        nb_code_score += 2
    if nb_analysis.get('has_ols'):
        nb_code_score += 2
    if nb_analysis.get('has_savefig') or nb_analysis.get('has_to_csv'):
        nb_code_score += 2
    score += nb_code_score
    feedback.append(f"Notebook code: {nb_code_score}/10")

    num_executed = nb_analysis.get('num_executed_cells', 0)
    if num_executed and num_executed >= 3:
        score += 5
    elif num_executed and num_executed > 0:
        score += 2

    csv_score = 0
    if result.get('csv_exists'):
        csv_score += 3
        if result.get('csv_created'):
            csv_score += 2
        if result.get('has_variable_col') or result.get('has_coefficient_col'):
            csv_score += 3
        csv_rows = result.get('csv_rows', 0)
        if csv_rows >= 4:
            csv_score += 2
    score += csv_score
    feedback.append(f"CSV: {csv_score}/10")

    plot_score = 0
    if result.get('plot_exists'):
        plot_score += 5
        if result.get('plot_created'):
            plot_score += 3
        if result.get('plot_size_kb', 0) >= 10:
            plot_score += 2
    score += plot_score
    feedback.append(f"Plot: {plot_score}/10")

    # =========================================
    # Part 2: Deep code analysis (30 pts)
    # =========================================
    execution_score = 0
    execution_verified = False

    temp_nb = tempfile.NamedTemporaryFile(delete=False, suffix='.ipynb')
    try:
        copy_from_env(
            metadata.get('expected_notebook_path',
                         '/home/ga/urbansim_projects/notebooks/hedonic_model.ipynb'),
            temp_nb.name
        )
        with open(temp_nb.name, 'r') as f:
            nb = json.load(f)

        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        all_code = ''
        for cell in code_cells:
            src = cell.get('source', '')
            if isinstance(src, list):
                src = ''.join(src)
            lines = [l for l in src.split('\n') if not l.strip().startswith('#')]
            all_code += '\n'.join(lines) + '\n'

        # Strip string literals to prevent gaming via keywords in strings
        clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
        clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)

        # Check for error outputs in executed cells
        has_errors = False
        for cell in code_cells:
            if cell.get('execution_count') is not None:
                for out in cell.get('outputs', []):
                    if out.get('output_type') == 'error':
                        has_errors = True
                        break

        has_data_load = bool(re.search(r'read_hdf|HDFStore', clean_code))
        has_regression = bool(re.search(r'(?:sm\.)?OLS\s*\(|LinearRegression\s*\(', clean_code))
        has_fit = bool(re.search(r'\.fit\s*\(', clean_code))
        has_features = len(re.findall(
            r'building_sqft|year_built|stories|residential_units|non_residential_sqft',
            clean_code, re.IGNORECASE))
        has_output_save = bool(re.search(r'\.to_csv\s*\(|\.savefig\s*\(', clean_code))

        if has_data_load:
            execution_score += 6
        if has_regression:
            execution_score += 8
        if has_fit:
            execution_score += 6
        if has_features >= 3:
            execution_score += 5
        elif has_features >= 1:
            execution_score += 2
        if has_output_save:
            execution_score += 5

        num_exec_cells = sum(1 for c in code_cells if c.get('execution_count') is not None)
        # Require no errors in executed cells for verification
        execution_verified = (has_data_load and has_regression and has_fit
                              and num_exec_cells >= 3 and not has_errors)

    except Exception as e:
        feedback.append(f"Notebook analysis error: {e}")
    finally:
        if os.path.exists(temp_nb.name):
            os.unlink(temp_nb.name)

    score += execution_score
    feedback.append(f"Code analysis: {execution_score}/30")

    # =========================================
    # Part 3: Output validation + VLM (30 pts)
    # =========================================
    output_score = 0

    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(
            metadata.get('expected_csv_path',
                         '/home/ga/urbansim_projects/output/hedonic_coefficients.csv'),
            temp_csv.name
        )
        import csv
        with open(temp_csv.name, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            cols = reader.fieldnames or []

        if len(rows) >= 2:
            output_score += 3

        coef_col = None
        for c in cols:
            if 'coef' in c.lower():
                coef_col = c
                break

        if coef_col:
            try:
                coeffs = [float(r[coef_col]) for r in rows if r.get(coef_col)]
                if len(coeffs) >= 2:
                    output_score += 3
                    if any(abs(c) > 0.001 for c in coeffs):
                        output_score += 4
            except (ValueError, TypeError):
                pass

    except Exception:
        pass
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    temp_plot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env(
            metadata.get('expected_plot_path',
                         '/home/ga/urbansim_projects/output/hedonic_scatter.png'),
            temp_plot.name
        )
        with open(temp_plot.name, 'rb') as f:
            header = f.read(8)
        if header[:4] == b'\x89PNG':
            output_score += 3
            if os.path.getsize(temp_plot.name) > 10 * 1024:
                output_score += 2
    except Exception:
        pass
    finally:
        if os.path.exists(temp_plot.name):
            os.unlink(temp_plot.name)

    # VLM verification (up to 15 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_first_screenshot, get_final_screenshot
            first = get_first_screenshot(traj)
            last = get_final_screenshot(traj)
            frames = sample_trajectory_frames(traj, num_samples=4)
            images = []
            if first:
                images.append(first)
            images.extend([f for f in frames if f not in images])
            if last and last not in images:
                images.append(last)
            if images:
                vlm_result = query_vlm(
                    images=images,
                    prompt=(
                        "These images show a GUI agent's work in Jupyter Lab building a hedonic regression model.\n"
                        "Image 1 is initial state, subsequent images show progress, last is final state.\n\n"
                        "Check the following (answer JSON):\n"
                        "1. 'regression_output_visible': Is there regression output (coefficients table, R-squared value, or OLS model summary) visible in the notebook?\n"
                        "2. 'plot_visible': Is a scatter plot or chart visible in the notebook output?\n"
                        "3. 'multiple_cells_executed': Are there multiple code cells with visible output (not just the template)?\n\n"
                        "Return JSON: {\"regression_output_visible\": bool, \"plot_visible\": bool, "
                        "\"multiple_cells_executed\": bool}"
                    )
                )
                if vlm_result and isinstance(vlm_result, dict) and vlm_result.get('success', True):
                    parsed = vlm_result.get('parsed', {})
                    vlm_pts = 0
                    if parsed.get('regression_output_visible'):
                        vlm_pts += 6
                    if parsed.get('plot_visible'):
                        vlm_pts += 5
                    if parsed.get('multiple_cells_executed'):
                        vlm_pts += 4
                    output_score += vlm_pts
                    feedback.append(f"VLM: {vlm_pts}/15")
        except Exception:
            pass

    score += output_score
    feedback.append(f"Output validation: {output_score}/30")

    passed = score >= 60 and execution_verified

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "; ".join(feedback)
    }
