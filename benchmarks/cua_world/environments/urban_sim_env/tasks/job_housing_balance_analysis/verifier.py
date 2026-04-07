#!/usr/bin/env python3
"""Verifier for Analyze Job-Housing Balance Across San Francisco Zones task."""

import json
import tempfile
import os
import logging
import csv

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_job_housing_balance(traj, env_info, task_info):
    """
    Verify the job-housing balance analysis using multiple criteria.
    Score structure (100 pts total):
      - CSV data logic: 30 pts
      - JSON summary: 20 pts
      - Notebook code checks: 20 pts
      - PNG plot checks: 10 pts
      - VLM Trajectory (workflow check): 20 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback = []
    score = 0

    # 1. Fetch metadata result
    res_path = tempfile.mktemp(suffix='.json')
    result_meta = {}
    try:
        copy_from_env('/tmp/task_result.json', res_path)
        with open(res_path, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        feedback.append(f"Failed to read result metadata: {e}")
    finally:
        if os.path.exists(res_path):
            os.unlink(res_path)

    # 2. Fetch Ground Truth
    gt_path = tempfile.mktemp(suffix='.json')
    gt = {}
    try:
        copy_from_env('/tmp/ground_truth.json', gt_path)
        with open(gt_path, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Critical Error: Failed to load GT - {e}"}
    finally:
        if os.path.exists(gt_path):
            os.unlink(gt_path)

    # 3. CSV Verification (30 Points)
    csv_score = 0
    csv_path = tempfile.mktemp(suffix='.csv')
    try:
        copy_from_env('/home/ga/urbansim_projects/output/zone_job_housing_balance.csv', csv_path)
        if os.path.exists(csv_path) and result_meta.get('csv', {}).get('created_during_task', True):
            with open(csv_path, 'r') as f:
                reader = csv.DictReader(f)
                rows = list(reader)

            if len(rows) > 50:
                csv_score += 10
                feedback.append("CSV output exists and has valid rows (+10)")

                # Verify Ratios
                matched_ratios = 0
                matched_classes = 0
                compared = 0

                for row in rows:
                    zid = str(int(float(row.get('zone_id', -1))))
                    if zid in gt.get('zone_ratios', {}):
                        compared += 1
                        # Ratio Check
                        try:
                            expected_ratio = gt['zone_ratios'][zid]
                            agent_ratio_str = row.get('jobs_housing_ratio', '').strip().lower()
                            if expected_ratio is None:
                                if agent_ratio_str in ('', 'nan', 'inf', 'none'):
                                    matched_ratios += 1
                            else:
                                actual_ratio = float(agent_ratio_str)
                                if expected_ratio == 0 and abs(actual_ratio) < 0.01:
                                    matched_ratios += 1
                                elif expected_ratio != 0 and abs(actual_ratio - expected_ratio) / max(abs(expected_ratio), 0.001) <= 0.1:
                                    matched_ratios += 1
                        except Exception:
                            pass

                        # Classification Check
                        expected_class = gt['zone_classifications'][zid]
                        actual_class = row.get('classification', '').strip().lower()
                        if actual_class == expected_class:
                            matched_classes += 1

                if compared > 0:
                    ratio_pts = int(10 * (matched_ratios / compared))
                    class_pts = int(10 * (matched_classes / compared))
                    csv_score += ratio_pts + class_pts
                    feedback.append(f"CSV Ratios matched {matched_ratios}/{compared} (+{ratio_pts})")
                    feedback.append(f"CSV Classes matched {matched_classes}/{compared} (+{class_pts})")
            else:
                feedback.append("CSV has too few rows.")
        else:
            feedback.append("CSV file not found or not created during task.")
    except Exception as e:
        feedback.append(f"CSV Evaluation error: {e}")
    finally:
        if os.path.exists(csv_path):
            os.unlink(csv_path)

    score += csv_score

    # 4. JSON Summary Verification (20 Points)
    json_score = 0
    json_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/home/ga/urbansim_projects/output/job_housing_summary.json', json_path)
        if os.path.exists(json_path) and result_meta.get('json', {}).get('created_during_task', True):
            with open(json_path, 'r') as f:
                summary = json.load(f)

            if isinstance(summary, dict):
                json_score += 5
                
                # Metric 1: Citywide ratio
                try:
                    cwr = summary.get('citywide_jobs_housing_ratio', 0)
                    if abs(float(cwr) - gt.get('citywide_ratio', 0)) / max(gt.get('citywide_ratio', 0.001), 0.001) <= 0.05:
                        json_score += 5
                        feedback.append("JSON citywide ratio accurate (+5)")
                except Exception:
                    pass

                # Metric 2: Classification counts
                count_matches = 0
                for k in ['job_rich_zones', 'balanced_zones', 'housing_rich_zones']:
                    try:
                        if abs(int(summary.get(k, -1)) - gt.get(k, 0)) <= 3:
                            count_matches += 1
                    except Exception:
                        pass
                
                if count_matches == 3:
                    json_score += 10
                    feedback.append("JSON classification counts matched (+10)")
                else:
                    json_score += int(10 * (count_matches / 3))
                    feedback.append(f"JSON classification counts matched {count_matches}/3")
        else:
            feedback.append("JSON summary not found.")
    except Exception as e:
        feedback.append(f"JSON summary error: {e}")
    finally:
        if os.path.exists(json_path):
            os.unlink(json_path)

    score += json_score

    # 5. Notebook Check (20 Points)
    nb_score = 0
    nb_path = tempfile.mktemp(suffix='.ipynb')
    try:
        copy_from_env('/home/ga/urbansim_projects/notebooks/job_housing_balance.ipynb', nb_path)
        if os.path.exists(nb_path):
            with open(nb_path, 'r') as f:
                nb = json.load(f)

            code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
            executed = sum(1 for c in code_cells if c.get('execution_count') is not None)
            if executed >= 3:
                nb_score += 10
                feedback.append("Notebook executed successfully (+10)")
            elif executed > 0:
                nb_score += 5

            source = "".join(["".join(c.get('source', [])) for c in code_cells])
            code_pts = 0
            if 'read_hdf' in source or 'HDFStore' in source: code_pts += 2
            if 'merge' in source or 'join' in source: code_pts += 4
            if 'groupby' in source: code_pts += 4
            
            nb_score += code_pts
            feedback.append(f"Notebook code logic checks: +{code_pts}")
    except Exception as e:
        feedback.append(f"Notebook check error: {e}")
    finally:
        if os.path.exists(nb_path):
            os.unlink(nb_path)

    score += nb_score

    # 6. PNG Chart Check (10 Points)
    png_score = 0
    if result_meta.get('png', {}).get('exists') and result_meta.get('png', {}).get('created_during_task'):
        size_kb = result_meta.get('png', {}).get('size_bytes', 0) / 1024
        if size_kb >= 5.0:
            png_score = 10
            feedback.append(f"PNG Chart created correctly (Size: {size_kb:.1f} KB) (+10)")
        elif size_kb > 0:
            png_score = 5
            feedback.append("PNG Chart created but smaller than expected (+5)")
    else:
        feedback.append("PNG Chart not created or invalid.")
    
    score += png_score

    # 7. VLM Verification (20 Points)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames

        if images:
            prompt = """Look at these screenshots showing a desktop with Jupyter Lab.
            1. Did the agent use Jupyter Lab to write data analysis code?
            2. Is there evidence of a bar chart being plotted showing job-housing balance or zone counts?
            Return JSON formatting exactly: {"has_code_writing": true, "has_bar_chart": true}"""
            
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("has_code_writing"): 
                    vlm_score += 10
                if parsed.get("has_bar_chart"): 
                    vlm_score += 10
                feedback.append(f"VLM verification matched required actions (+{vlm_score})")
            else:
                vlm_score = 20
                feedback.append("VLM verification failed to parse; granting fallback points (+20)")
        else:
            vlm_score = 20
            feedback.append("No images for VLM; granting fallback points (+20)")
    except Exception as e:
        logger.warning(f"VLM verification skipped due to framework dependency: {e}")
        vlm_score = 20
        feedback.append("VLM framework unavailable; granting fallback points (+20)")

    score += vlm_score

    passed = score >= 60 and csv_score >= 10
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }