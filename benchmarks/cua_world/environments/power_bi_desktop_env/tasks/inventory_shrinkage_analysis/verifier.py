#!/usr/bin/env python3
"""
Verifier for inventory_shrinkage_analysis task.

Checks:
1. PBIX File exists and contains required measures/columns (Strings in DataModel/Layout).
2. Report contains Scatter Plot and Card visuals.
3. Exported CSV exists.
4. Exported CSV data matches Ground Truth (calculated from input data).
   - This validates the DAX logic (Negative variance filter + Sum + Abs) was correct.

Score Distribution:
- PBIX Saved: 10
- Data Loaded & Model Structure: 20 (Variance_Value column present)
- DAX Measure Logic: 30 (Verified via CSV output numbers)
- Visuals: 20 (Scatter + Card)
- Export Accuracy: 20 (CSV matches ground truth)
"""

import json
import os
import tempfile
import logging
import csv
import io

logger = logging.getLogger(__name__)

def verify_inventory_shrinkage(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env("C:/Users/Docker/Desktop/shrinkage_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    details = {}

    # Extract data from result
    pbix_exists = result.get('pbix_exists', False)
    csv_exists = result.get('csv_exists', False)
    layout_search = result.get('layout_search', '')
    model_search = result.get('model_search', '')
    csv_sample = result.get('csv_sample', '')
    
    # Parse Ground Truth
    ground_truth_raw = result.get('ground_truth', '{}')
    if isinstance(ground_truth_raw, str):
        try:
            ground_truth = json.loads(ground_truth_raw)
        except:
            ground_truth = {}
    else:
        ground_truth = ground_truth_raw
        
    truth_total = ground_truth.get('total_shrinkage_truth', 0)
    truth_top_store = ground_truth.get('top_store_truth', '')
    truth_top_loss = ground_truth.get('top_loss_truth', 0)

    # --- 1. PBIX Existence (10 pts) ---
    if pbix_exists and result.get('pbix_size_bytes', 0) > 5000:
        score += 10
        feedback_parts.append("PBIX file saved.")
    else:
        feedback_parts.append("PBIX file not found or too small.")

    # --- 2. Model Structure (20 pts) ---
    # Check for calculated column
    combined_search = (layout_search + model_search).replace('\x00', '')
    if "Variance_Value" in combined_search or "VarianceValue" in combined_search:
        score += 20
        feedback_parts.append("Variance_Value calculated column found.")
    else:
        feedback_parts.append("Variance_Value column not detected.")

    # --- 3. Visuals (20 pts) ---
    has_scatter = "scatterChart" in layout_search or "scatter" in layout_search.lower()
    has_card = "card" in layout_search.lower()
    
    if has_scatter:
        score += 10
        feedback_parts.append("Scatter plot found.")
    else:
        feedback_parts.append("Scatter plot missing.")
        
    if has_card:
        score += 10
        feedback_parts.append("Card visual found.")
    else:
        feedback_parts.append("Card visual missing.")

    # --- 4. Export & DAX Logic Accuracy (50 pts total) ---
    # We verify the DAX logic by checking the numbers in the exported CSV.
    # If the DAX is wrong (e.g. sum of all variance instead of just negative), the numbers won't match.
    
    if csv_exists:
        score += 10 # Base points for exporting
        
        # Parse agent's CSV
        try:
            csv_io = io.StringIO(csv_sample)
            reader = csv.DictReader(csv_io)
            rows = list(reader)
            
            if len(rows) > 0:
                # Check sort order (descending loss)
                try:
                    first_val = float(rows[0].get('Shrinkage_Loss', 0))
                    second_val = float(rows[1].get('Shrinkage_Loss', 0))
                    if first_val >= second_val:
                        score += 10
                        feedback_parts.append("Export sorted correctly.")
                    else:
                        feedback_parts.append("Export not sorted descending.")
                except:
                    feedback_parts.append("Could not verify sort order.")

                # Check Value Accuracy (Tolerance 2%)
                # We check the top store's loss
                agent_top_loss = float(rows[0].get('Shrinkage_Loss', 0))
                
                # Check if it matches Truth
                if abs(agent_top_loss - truth_top_loss) < (truth_top_loss * 0.02):
                    score += 30
                    feedback_parts.append(f"DAX Logic Verified: Top store loss ({agent_top_loss}) matches ground truth.")
                else:
                    feedback_parts.append(f"DAX Logic incorrect. Expected top loss ~{truth_top_loss}, got {agent_top_loss}.")
                    # Check if they perhaps calculated sum of ALL variance (including overage)
                    # We can't easily check that without calculating it, but usually mismatch means logic error.
            else:
                feedback_parts.append("Exported CSV is empty.")
        except Exception as e:
            feedback_parts.append(f"Failed to parse exported CSV: {e}")
    else:
        feedback_parts.append("worst_stores.csv not found.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }