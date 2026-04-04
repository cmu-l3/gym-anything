#!/usr/bin/env python3
"""Verifier for run_simulation_year task."""

import json
import tempfile
import os
import re


def verify_simulation_year(traj, env_info, task_info):
    """Verify simulation was run successfully.

    Scoring (100 points total):
    - Programmatic checks (40 pts): notebook, CSV, plot
    - Code analysis (30 pts): orca usage, simulation steps, execution
    - Output validation + VLM (30 pts): CSV content, plot validity, VLM check
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    # Part 1: Task result (40 pts)
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    if result.get('notebook_exists') and result.get('notebook_modified'):
        score += 5

    nb_a = result.get('notebook_analysis', {})
    code_score = 0
    if nb_a.get('has_code'):
        code_score += 2
    if nb_a.get('has_orca'):
        code_score += 3
    if nb_a.get('has_add_table'):
        code_score += 3
    if nb_a.get('has_orca_step'):
        code_score += 2
    score += code_score
    feedback.append(f"Notebook code: {code_score}/10")

    num_exec = nb_a.get('num_executed_cells', 0)
    if num_exec and num_exec >= 3:
        score += 5
    elif num_exec and num_exec > 0:
        score += 2

    csv_score = 0
    if result.get('csv_exists'):
        csv_score += 3
        if result.get('csv_created'):
            csv_score += 2
        if result.get('has_metric_col'):
            csv_score += 2
        if result.get('has_before_col') and result.get('has_after_col'):
            csv_score += 3
    score += csv_score
    feedback.append(f"CSV: {csv_score}/10")

    plot_score = 0
    if result.get('plot_exists'):
        plot_score += 5
        if result.get('plot_created'):
            plot_score += 3
        if result.get('plot_size_kb', 0) >= 5:
            plot_score += 2
    score += plot_score
    feedback.append(f"Plot: {plot_score}/10")

    # Part 2: Deep notebook analysis (30 pts)
    exec_score = 0
    execution_verified = False

    temp_nb = tempfile.NamedTemporaryFile(delete=False, suffix='.ipynb')
    try:
        copy_from_env(
            metadata.get('expected_notebook_path',
                         '/home/ga/urbansim_projects/notebooks/simulation.ipynb'),
            temp_nb.name
        )
        with open(temp_nb.name, 'r') as f:
            nb = json.load(f)

        all_code = ''
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
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

        has_orca = bool(re.search(r'import orca|from orca', clean_code))
        has_add_table = bool(re.search(r'orca\.add_table\s*\(', clean_code))
        has_step = bool(re.search(r'orca\.step\s*\(|@orca\.step', clean_code))
        has_run = bool(re.search(r'orca\.run\s*\(', clean_code))
        has_data_load = bool(re.search(r'read_hdf|HDFStore', clean_code))
        has_year = bool(re.search(r'iter_var', clean_code))
        has_summary = bool(re.search(r'\.mean\s*\(\)|\.count\s*\(\)|\.describe\s*\(\)', clean_code))

        if has_orca:
            exec_score += 5
        if has_add_table:
            exec_score += 5
        if has_step:
            exec_score += 5
        if has_run:
            exec_score += 5
        if has_data_load:
            exec_score += 5
        if has_year:
            exec_score += 3
        if has_summary:
            exec_score += 2

        num_exec_cells = sum(1 for c in code_cells if c.get('execution_count') is not None)
        execution_verified = (has_orca and has_run and has_data_load
                              and num_exec_cells >= 3 and not has_errors)

    except Exception as e:
        feedback.append(f"Notebook analysis error: {e}")
    finally:
        if os.path.exists(temp_nb.name):
            os.unlink(temp_nb.name)

    score += exec_score
    feedback.append(f"Code analysis: {exec_score}/30")

    # Part 3: Output validation + VLM (30 pts)
    output_score = 0

    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(
            metadata.get('expected_csv_path',
                         '/home/ga/urbansim_projects/output/simulation_summary.csv'),
            temp_csv.name
        )
        import csv
        with open(temp_csv.name, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            cols = reader.fieldnames or []

        if len(rows) >= 2:
            output_score += 3

        before_col = None
        after_col = None
        for c in cols:
            if 'before' in c.lower():
                before_col = c
            if 'after' in c.lower():
                after_col = c

        if before_col and after_col and len(rows) >= 2:
            try:
                before_vals = [float(r[before_col]) for r in rows if r.get(before_col)]
                after_vals = [float(r[after_col]) for r in rows if r.get(after_col)]
                if len(before_vals) >= 2 and len(after_vals) >= 2:
                    output_score += 4
                    # Check that before and after values actually differ (simulation did something)
                    if any(abs(b - a) > 0.001 for b, a in zip(before_vals, after_vals)):
                        output_score += 3
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
                         '/home/ga/urbansim_projects/output/simulation_comparison.png'),
            temp_plot.name
        )
        with open(temp_plot.name, 'rb') as f:
            header = f.read(8)
        if header[:4] == b'\x89PNG':
            output_score += 3
            if os.path.getsize(temp_plot.name) > 5 * 1024:
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
                        "These images show a GUI agent running an UrbanSim simulation in Jupyter Lab.\n"
                        "Image 1 is initial state, subsequent images show progress, last is final state.\n\n"
                        "Check the following (answer JSON):\n"
                        "1. 'simulation_output_visible': Is there simulation output (metrics, before/after comparison, summary statistics) visible in the notebook?\n"
                        "2. 'chart_visible': Is a comparison bar chart visible in the notebook?\n"
                        "3. 'multiple_cells_executed': Are there multiple code cells with visible output (not just the template)?\n\n"
                        "Return JSON: {\"simulation_output_visible\": bool, \"chart_visible\": bool, "
                        "\"multiple_cells_executed\": bool}"
                    )
                )
                if vlm_result and isinstance(vlm_result, dict) and vlm_result.get('success', True):
                    parsed = vlm_result.get('parsed', {})
                    vlm_pts = 0
                    if parsed.get('simulation_output_visible'):
                        vlm_pts += 6
                    if parsed.get('chart_visible'):
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
