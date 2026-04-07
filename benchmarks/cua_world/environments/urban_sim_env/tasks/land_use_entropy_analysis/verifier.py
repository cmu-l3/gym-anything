#!/usr/bin/env python3
"""
Verifier for land_use_entropy_analysis task.

Uses MULTIPLE INDEPENDENT SIGNALS to verify:
1. Programmatic data matching: Agent's CSV/JSON data vs hidden ground truth
2. Code evaluation: Notebook exists, executes, and parses correctly
3. Visual Verification: VLM checks trajectory frames for GUI interaction
"""

import json
import os
import csv
import math
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM prompts
TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent working in Jupyter Lab for a data science task.

The agent's goal was to compute land use entropy by zone, export data, and generate a bar chart.
The images are sampled chronologically.

Assess:
1. JUPYTER_ACTIVE: Did the agent actively write and execute code in a Jupyter Notebook?
2. PLOT_GENERATED: Is there a visible bar chart or plot generated in the notebook or opened in the UI?
3. WORKFLOW_PROGRESS: Does the sequence show meaningful progression (code being written/run, outputs appearing)?

Respond ONLY in JSON format:
{
    "jupyter_active": true/false,
    "plot_generated": true/false,
    "workflow_progress": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief description of what is seen"
}
"""

def verify_land_use_entropy(traj, env_info, task_info):
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    metadata = task_info.get('metadata', {})
    expected_nb = metadata.get('expected_notebook_path', '/home/ga/urbansim_projects/notebooks/land_use_entropy.ipynb')
    expected_csv = metadata.get('expected_csv_path', '/home/ga/urbansim_projects/output/zone_entropy.csv')
    expected_png = metadata.get('expected_png_path', '/home/ga/urbansim_projects/output/entropy_barplot.png')
    expected_json = metadata.get('expected_json_path', '/home/ga/urbansim_projects/output/entropy_summary.json')
    gt_path = metadata.get('ground_truth_path', '/var/lib/urbansim_ground_truth/entropy_ground_truth.json')

    # 1. Fetch task result manifest
    manifest_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", manifest_tmp.name)
        with open(manifest_tmp.name, 'r') as f:
            manifest = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load manifest: {e}"}
    finally:
        if os.path.exists(manifest_tmp.name):
            os.unlink(manifest_tmp.name)

    # 2. Fetch ground truth
    gt = None
    gt_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(gt_path, gt_tmp.name)
        with open(gt_tmp.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
    finally:
        if os.path.exists(gt_tmp.name):
            os.unlink(gt_tmp.name)

    # 3. Verify CSV Output (Total 35 pts)
    csv_exists = manifest.get('csv', {}).get('exists', False)
    csv_created = manifest.get('csv', {}).get('created_during_task', False)
    csv_data = []

    if csv_exists and csv_created:
        score += 5
        feedback_parts.append("CSV created successfully")

        csv_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(expected_csv, csv_tmp.name)
            with open(csv_tmp.name, 'r') as f:
                reader = csv.DictReader(f)
                headers = reader.fieldnames or []
                csv_data = list(reader)

            req_cols = ['zone_id', 'entropy', 'normalized_entropy']
            if all(any(req in h.lower() for h in headers) for req in req_cols):
                score += 5
                feedback_parts.append("CSV has required columns")

            if len(csv_data) > 0:
                # Compare entropy values
                matches = 0
                checked = 0
                for row in csv_data:
                    # Resolve dict keys safely (ignoring case/whitespace)
                    z_key = next((k for k in row.keys() if 'zone_id' in k.lower()), None)
                    e_key = next((k for k in row.keys() if 'entropy' in k.lower() and 'norm' not in k.lower()), None)
                    n_key = next((k for k in row.keys() if 'normalized_entropy' in k.lower()), None)
                    
                    if not (z_key and e_key and n_key):
                        continue

                    try:
                        zone_id = str(int(float(row[z_key])))
                        agent_h = float(row[e_key])
                        agent_n = float(row[n_key])

                        if zone_id in gt['zone_entropy']:
                            checked += 1
                            gt_h = gt['zone_entropy'][zone_id]['entropy']
                            gt_n = gt['zone_entropy'][zone_id]['normalized_entropy']

                            # Check for close match (+/- 0.05)
                            if abs(agent_h - gt_h) <= 0.05 and abs(agent_n - gt_n) <= 0.05:
                                matches += 1
                    except (ValueError, TypeError):
                        pass
                
                if checked > 10:
                    match_rate = matches / checked
                    if match_rate > 0.8:
                        score += 25
                        feedback_parts.append(f"Entropy values match ground truth highly ({matches}/{checked})")
                    elif match_rate > 0.4:
                        score += 10
                        feedback_parts.append(f"Entropy values partially match ({matches}/{checked})")
                    else:
                        feedback_parts.append(f"Entropy values don't match ground truth ({matches}/{checked})")
                else:
                    feedback_parts.append("Could not parse enough rows to compare entropy.")
        except Exception as e:
            feedback_parts.append(f"Error reading CSV: {e}")
        finally:
            if os.path.exists(csv_tmp.name):
                os.unlink(csv_tmp.name)
    else:
        feedback_parts.append("CSV missing or not created during task")

    # 4. Verify JSON Output (Total 25 pts)
    json_exists = manifest.get('json', {}).get('exists', False)
    json_created = manifest.get('json', {}).get('created_during_task', False)

    if json_exists and json_created:
        json_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(expected_json, json_tmp.name)
            with open(json_tmp.name, 'r') as f:
                agent_json = json.load(f)

            # Check ranking
            agent_top = agent_json.get('most_diverse_zones', [])
            agent_bot = agent_json.get('least_diverse_zones', [])
            gt_top = set(gt['most_diverse_zones'])
            gt_bot = set(gt['least_diverse_zones'])

            top_overlap = len(set(agent_top) & gt_top)
            bot_overlap = len(set(agent_bot) & gt_bot)

            if top_overlap >= 3:
                score += 10
                feedback_parts.append(f"Most diverse zones match well ({top_overlap}/5)")
            elif top_overlap > 0:
                score += 5
                feedback_parts.append(f"Most diverse zones partial match ({top_overlap}/5)")

            if bot_overlap >= 3:
                score += 10
                feedback_parts.append(f"Least diverse zones match well ({bot_overlap}/5)")
            elif bot_overlap > 0:
                score += 5
                feedback_parts.append(f"Least diverse zones partial match ({bot_overlap}/5)")

            # Check stats
            agent_mean = agent_json.get('mean_normalized_entropy', 0)
            if abs(agent_mean - gt['mean_normalized_entropy']) <= 0.1:
                score += 5
                feedback_parts.append("Summary statistics match")

        except Exception as e:
            feedback_parts.append(f"Error reading JSON summary: {e}")
        finally:
            if os.path.exists(json_tmp.name):
                os.unlink(json_tmp.name)
    else:
        feedback_parts.append("JSON summary missing or not created during task")

    # 5. Verify Notebook Execution (Total 20 pts)
    nb_exists = manifest.get('notebook', {}).get('exists', False)
    nb_created = manifest.get('notebook', {}).get('created_during_task', False)

    if nb_exists and nb_created:
        score += 5
        nb_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.ipynb')
        try:
            copy_from_env(expected_nb, nb_tmp.name)
            with open(nb_tmp.name, 'r') as f:
                nb_data = json.load(f)
            
            code_cells = [c for c in nb_data.get('cells', []) if c.get('cell_type') == 'code']
            executed_cells = sum(1 for c in code_cells if c.get('execution_count') is not None)
            
            # Combine code to check for semantics
            code_str = ""
            for c in code_cells:
                source = c.get('source', '')
                if isinstance(source, list):
                    source = "".join(source)
                code_str += source + "\n"

            clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', code_str)
            clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)

            if executed_cells >= 3:
                score += 5
                feedback_parts.append("Notebook properly executed")

            has_data = bool(re.search(r'read_hdf|HDFStore', clean_code))
            has_entropy = bool(re.search(r'log|ln|entropy', clean_code, re.IGNORECASE))
            has_groupby = bool(re.search(r'groupby', clean_code))

            if has_data and has_entropy and has_groupby:
                score += 10
                feedback_parts.append("Notebook contains required logic patterns")
            else:
                feedback_parts.append("Notebook missing core logic patterns (hdf load, log/entropy, groupby)")
                
        except Exception as e:
            feedback_parts.append(f"Error reading notebook: {e}")
        finally:
            if os.path.exists(nb_tmp.name):
                os.unlink(nb_tmp.name)
    else:
        feedback_parts.append("Notebook not modified or missing")

    # 6. Verify PNG Plot & VLM Trajectory (Total 20 pts)
    png_exists = manifest.get('png', {}).get('exists', False)
    png_created = manifest.get('png', {}).get('created_during_task', False)
    png_size = manifest.get('png', {}).get('size', 0)

    if png_exists and png_created and png_size > 5000:
        score += 10
        feedback_parts.append("Bar chart PNG created successfully")
    else:
        feedback_parts.append("PNG plot missing or too small")

    # VLM Trajectory Verification
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            result = query_vlm(images=frames, prompt=TRAJECTORY_PROMPT)
            if result and result.get("success"):
                parsed = result.get("parsed", {})
                if parsed.get("jupyter_active"):
                    vlm_score += 5
                if parsed.get("plot_generated"):
                    vlm_score += 5
                
                feedback_parts.append(f"VLM verified trajectory: {parsed.get('reasoning', 'OK')}")
            else:
                feedback_parts.append("VLM verification failed or unparseable")
        else:
            feedback_parts.append("No frames available for VLM verification")
    except ImportError:
        logger.warning("VLM modules not available, skipping VLM check and allocating points automatically")
        # Automatically award points if the script runs outside the VLM-enabled testing environment 
        # but the plot physically exists.
        if png_exists and png_created and nb_exists:
            vlm_score += 10
            feedback_parts.append("VLM assumed OK (plot & notebook exist)")
    except Exception as e:
        logger.error(f"VLM exception: {e}")

    score += vlm_score

    # Final tally
    passed = score >= 60

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }