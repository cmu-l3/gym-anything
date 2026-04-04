#!/usr/bin/env python3
"""
Verifier for compute_hydrograph_shape task.
Checks:
1. Output files exist and were created during task.
2. CSV has correct structure.
3. Computed values match ground truth (tolerated range).
4. Physical consistency of results.
5. Summary file classification.
"""

import json
import csv
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_hydrograph_shape(traj, env_info, task_info):
    """
    Verify the hydrograph shape analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    agent_csv_path = "/home/ga/Documents/hec_ras_results/hydrograph_shape_params.csv"
    agent_summary_path = "/home/ga/Documents/hec_ras_results/hydrograph_shape_summary.txt"
    ref_json_path = "/tmp/hydrograph_shape_reference.json"
    result_json_path = "/tmp/task_result.json"

    # Temporary files on host
    tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
    tmp_summary = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    tmp_ref = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name

    files_retrieved = {}
    
    try:
        # 1. Retrieve files
        try:
            copy_from_env(result_json_path, tmp_res)
            with open(tmp_res, 'r') as f:
                task_stats = json.load(f)
            files_retrieved['stats'] = True
        except:
            task_stats = {}
            
        try:
            copy_from_env(agent_csv_path, tmp_csv)
            files_retrieved['csv'] = True
        except:
            pass
            
        try:
            copy_from_env(agent_summary_path, tmp_summary)
            files_retrieved['summary'] = True
        except:
            pass
            
        try:
            copy_from_env(ref_json_path, tmp_ref)
            with open(tmp_ref, 'r') as f:
                reference_data = json.load(f)
            files_retrieved['ref'] = True
        except:
            reference_data = {"error": "Could not retrieve reference data"}

        # SCORING START
        score = 0
        feedback = []
        
        # Criterion 1: Files Existence (20 pts)
        if task_stats.get("csv_exists") and task_stats.get("csv_modified"):
            score += 10
            feedback.append("CSV file created.")
        elif task_stats.get("csv_exists"):
            score += 5
            feedback.append("CSV exists but timestamp check failed.")
        else:
            feedback.append("CSV file missing.")

        if task_stats.get("summary_exists") and task_stats.get("summary_modified"):
            score += 10
            feedback.append("Summary file created.")
        elif task_stats.get("summary_exists"):
            score += 5
            feedback.append("Summary exists but timestamp check failed.")
        else:
            feedback.append("Summary file missing.")

        # Stop if no CSV
        if not files_retrieved.get('csv'):
            return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

        # Load Agent CSV
        agent_data = []
        try:
            with open(tmp_csv, 'r') as f:
                # Handle potential header issues by reading snippets first
                content = f.read()
                f.seek(0)
                if not content.strip():
                    raise ValueError("Empty CSV")
                reader = csv.DictReader(f)
                agent_data = list(reader)
        except Exception as e:
            feedback.append(f"Failed to parse CSV: {str(e)}")
            return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

        # Criterion 2: CSV Structure and Row Count (10 pts)
        # Expected columns (fuzzy match)
        expected_cols = ["River_Station", "Q_base_cfs", "Q_peak_cfs", "T_rise_hr", "T_rec_hr", "R_ratio", "W50_hr", "W75_hr", "P_coeff"]
        
        # Normalize agent keys
        if agent_data:
            keys = agent_data[0].keys()
            normalized_keys = [k.lower().replace(" ", "_").replace("-", "_") for k in keys]
            
            # Check for essential columns
            essential = ["station", "peak", "base", "rise", "rec", "ratio", "50", "75", "coeff"]
            found_cols = 0
            for ess in essential:
                if any(ess in k for k in normalized_keys):
                    found_cols += 1
            
            if found_cols >= 7:
                score += 5
                feedback.append("CSV columns look correct.")
            else:
                feedback.append(f"CSV missing expected columns. Found matches for {found_cols}/9 keywords.")

            if len(agent_data) == 3:
                score += 5
                feedback.append("Correct number of rows (3).")
            else:
                feedback.append(f"Incorrect row count: {len(agent_data)} (expected 3).")
        else:
            feedback.append("CSV has no data.")

        # Criterion 3: Value Accuracy (60 pts)
        # Compare against reference
        if files_retrieved.get('ref') and "targets" in reference_data:
            ref_targets = reference_data["targets"]
            
            # Try to match agent rows to reference rows
            # Strategy: Match by river station name if possible, otherwise by relative magnitude of peak flow
            # (since indices 0, mid, -1 have specific flow characteristics)
            
            matches_found = 0
            val_score = 0
            
            for row in agent_data:
                # Extract agent values
                try:
                    # Helper to get float from row with fuzzy key
                    def get_val(keywords):
                        for k, v in row.items():
                            k_norm = k.lower().replace(" ", "_")
                            if any(kw in k_norm for kw in keywords):
                                return float(v)
                        return None
                    
                    row_rs = None
                    for k, v in row.items():
                        if "station" in k.lower() or "rs" in k.lower():
                            row_rs = str(v).strip()
                            break
                            
                    a_peak = get_val(["peak", "max"])
                    a_base = get_val(["base", "min"])
                    a_rise = get_val(["rise"])
                    a_rec = get_val(["rec"])
                    a_ratio = get_val(["ratio"])
                    a_w50 = get_val(["w50", "50"])
                    a_coeff = get_val(["coeff", "peaked"])

                    if a_peak is None: continue

                    # Find matching reference target
                    best_target = None
                    min_peak_diff = float('inf')
                    
                    for rs_key, target in ref_targets.items():
                        # Try string match
                        if row_rs and (row_rs in rs_key or rs_key in row_rs):
                            best_target = target
                            break
                        
                        # Fallback: numeric peak match (within 5%)
                        diff = abs(target["Q_peak"] - a_peak) / target["Q_peak"]
                        if diff < 0.05 and diff < min_peak_diff:
                            min_peak_diff = diff
                            best_target = target
                    
                    if best_target:
                        matches_found += 1
                        t = best_target
                        
                        # Score this row (Max 20 pts per row -> 60 total)
                        row_pts = 0
                        
                        # Peak & Base (5 pts)
                        if abs(a_peak - t["Q_peak"]) / t["Q_peak"] < 0.1: row_pts += 2.5
                        if abs(a_base - t["Q_base"]) / (abs(t["Q_base"]) + 1) < 0.1: row_pts += 2.5 # Handle 0 base
                        
                        # Timing (5 pts) - tolerate 0.5 hr abs diff or 20% rel diff
                        if abs(a_rise - t["T_rise"]) < 0.5 or abs(a_rise - t["T_rise"]) / (t["T_rise"]+0.1) < 0.2: row_pts += 2.5
                        if abs(a_rec - t["T_rec"]) < 0.5 or abs(a_rec - t["T_rec"]) / (t["T_rec"]+0.1) < 0.2: row_pts += 2.5
                        
                        # Shape (5 pts)
                        if abs(a_ratio - t["R_ratio"]) < 0.1 or abs(a_ratio - t["R_ratio"]) / t["R_ratio"] < 0.2: row_pts += 2
                        if abs(a_coeff - t["P_coeff"]) < 0.1 or abs(a_coeff - t["P_coeff"]) / t["P_coeff"] < 0.2: row_pts += 3
                        
                        # Widths (5 pts)
                        if abs(a_w50 - t["W50"]) < 0.5 or abs(a_w50 - t["W50"]) / (t["W50"]+0.1) < 0.2: row_pts += 5
                        
                        val_score += row_pts
                        
                except Exception as e:
                    logger.warning(f"Error parsing row: {e}")
                    continue

            # Scale score if we matched fewer rows
            # We expect 3 rows. Cap at 60.
            val_score = min(60, val_score)
            score += val_score
            if matches_found > 0:
                feedback.append(f"Matched {matches_found} cross-sections. Data accuracy score: {val_score:.1f}/60")
            else:
                feedback.append("Could not match any rows to reference data (values too divergent).")

        else:
            # Fallback if reference generation failed (shouldn't happen)
            # Check physical consistency
            consistent = True
            for row in agent_data:
                try:
                    q_p = float(row.get("Q_peak_cfs", 0))
                    q_b = float(row.get("Q_base_cfs", 0))
                    w50 = float(row.get("W50_hr", 0))
                    w75 = float(row.get("W75_hr", 0))
                    if q_p <= q_b: consistent = False
                    if w75 >= w50 and w50 > 0: consistent = False
                except: pass
            
            if consistent and len(agent_data) == 3:
                score += 30
                feedback.append("Reference missing, but data is physically consistent.")

        # Criterion 4: Summary Classification (10 pts)
        if files_retrieved.get('summary'):
            try:
                with open(tmp_summary, 'r') as f:
                    content = f.read().lower()
                    
                terms = ["fast-rising", "symmetric", "slow-rising", "fast rising", "slow rising"]
                found_terms = sum(1 for t in terms if t in content)
                
                if found_terms >= 1:
                    score += 10
                    feedback.append("Summary file contains classification terms.")
                else:
                    feedback.append("Summary file missing required classification terms.")
            except:
                pass

        return {
            "passed": score >= 60,
            "score": int(score),
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        for f in [tmp_csv, tmp_summary, tmp_ref, tmp_res]:
            if os.path.exists(f):
                os.unlink(f)