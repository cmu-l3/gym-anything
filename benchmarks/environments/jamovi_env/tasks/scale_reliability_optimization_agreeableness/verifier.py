#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import math
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_cronbach_alpha(items_data):
    """
    Calculate Cronbach's Alpha for a list of items (list of lists or similar).
    items_data: list of rows, where each row is a list of item scores.
    """
    # Transpose to get columns (items)
    n_items = len(items_data[0])
    n_subjects = len(items_data)
    
    if n_items < 2:
        return 0.0

    item_variances = []
    total_scores = [0] * n_subjects
    
    # Calculate item variances and total scores
    for col_idx in range(n_items):
        col_values = [row[col_idx] for row in items_data]
        mean = sum(col_values) / n_subjects
        variance = sum((x - mean) ** 2 for x in col_values) / (n_subjects - 1)
        item_variances.append(variance)
        
        for row_idx, val in enumerate(col_values):
            total_scores[row_idx] += val
            
    # Calculate variance of total scores
    total_mean = sum(total_scores) / n_subjects
    total_variance = sum((x - total_mean) ** 2 for x in total_scores) / (n_subjects - 1)
    
    if total_variance == 0:
        return 0.0

    # Cronbach's Alpha Formula
    sum_item_variances = sum(item_variances)
    alpha = (n_items / (n_items - 1)) * (1 - (sum_item_variances / total_variance))
    
    return alpha

def parse_report_file(file_path):
    """Reads the 3 lines from the report file."""
    try:
        with open(file_path, 'r') as f:
            lines = [l.strip() for l in f.readlines() if l.strip()]
        if len(lines) < 3:
            return None, "File has fewer than 3 lines"
        return lines, None
    except Exception as e:
        return None, str(e)

def verify_scale_reliability(traj, env_info, task_info):
    """
    Verifies the scale reliability task.
    1. Checks if output files exist and were created during task.
    2. Calculates ground truth Alpha using the dataset (handling reverse coding).
    3. Compares agent's report against ground truth.
    4. Inspects OMV file to ensure correct configuration (A1 reversed).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # Files to retrieve
    files = {
        "result": "/tmp/task_result.json",
        "omv": "/tmp/result_project.omv",
        "report": "/tmp/result_report.txt",
        "data": "/tmp/ground_truth_data.csv"
    }
    
    local_files = {}
    temp_dir = tempfile.mkdtemp()
    
    try:
        # Copy files from env
        for name, path in files.items():
            local_path = os.path.join(temp_dir, os.path.basename(path))
            try:
                copy_from_env(path, local_path)
                local_files[name] = local_path
            except Exception as e:
                logger.warning(f"Could not copy {path}: {e}")

        # Load Result JSON
        if "result" not in local_files:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result JSON"}
            
        with open(local_files["result"], 'r') as f:
            result_data = json.load(f)

        # Basic Checks (20 pts)
        if result_data.get("omv_exists") and result_data.get("omv_created_during_task"):
            score += 10
            feedback.append("Project file created.")
        
        if result_data.get("report_exists") and result_data.get("report_created_during_task"):
            score += 10
            feedback.append("Report file created.")
        else:
            feedback.append("Report file missing or not created during task.")
            # Critical failure if no report
            return {"passed": False, "score": score, "feedback": " ".join(feedback)}

        # ---------------------------------------------------------------------
        # Ground Truth Calculation
        # ---------------------------------------------------------------------
        if "data" not in local_files:
             return {"passed": False, "score": score, "feedback": "Could not retrieve dataset for verification"}

        # Read CSV simply (avoiding pandas dependency if possible, but standard python csv is fine)
        import csv
        data_rows = []
        header = []
        try:
            with open(local_files["data"], 'r') as f:
                reader = csv.reader(f)
                header = next(reader)
                # Find indices for A1-A5
                try:
                    indices = [header.index(c) for c in ["A1", "A2", "A3", "A4", "A5"]]
                except ValueError:
                    return {"passed": False, "score": score, "feedback": "Dataset missing required columns A1-A5"}
                
                for row in reader:
                    try:
                        # Convert to int/float
                        vals = [float(row[i]) for i in indices]
                        # Validate range 1-6
                        if all(1 <= v <= 6 for v in vals):
                            data_rows.append(vals)
                    except ValueError:
                        continue # Skip bad rows
        except Exception as e:
             return {"passed": False, "score": score, "feedback": f"Error processing dataset: {e}"}

        if not data_rows:
             return {"passed": False, "score": score, "feedback": "No valid data rows found in dataset"}

        # Reverse code A1 (Index 0 in our extracted list)
        # Scale 1-6 -> 7 - x
        processed_data = []
        for row in data_rows:
            new_row = list(row)
            new_row[0] = 7 - new_row[0] # Reverse A1
            processed_data.append(new_row)
        
        # Calculate Overall Alpha
        ground_truth_alpha = calculate_cronbach_alpha(processed_data)
        
        # Calculate "If Dropped" Alphas
        dropped_alphas = {}
        item_names = ["A1", "A2", "A3", "A4", "A5"]
        for i in range(5):
            # Create subset excluding item i
            subset_data = [[r[j] for j in range(5) if j != i] for r in processed_data]
            dropped_alphas[item_names[i]] = calculate_cronbach_alpha(subset_data)
            
        best_dropped_item = max(dropped_alphas, key=dropped_alphas.get)
        best_dropped_alpha = dropped_alphas[best_dropped_item]
        
        # If dropping makes it worse (lower alpha), then "None" is the answer
        # But usually in these tasks we ask for the highest *possible* alpha if *one* is dropped,
        # even if it's lower than the total. 
        # Task description: "The highest possible alpha if one item is dropped... The name of the item... If dropping no item improves the alpha... write 'None'"
        
        should_drop = False
        target_item_name = "None"
        target_alpha_val = best_dropped_alpha # This is the max of the dropped options
        
        if best_dropped_alpha > ground_truth_alpha:
            should_drop = True
            target_item_name = best_dropped_item
        
        # ---------------------------------------------------------------------
        # Verify Report Content (60 pts)
        # ---------------------------------------------------------------------
        if "report" in local_files:
            lines, error = parse_report_file(local_files["report"])
            if lines:
                # Line 1: Overall Alpha
                try:
                    reported_alpha = float(lines[0])
                    if abs(reported_alpha - ground_truth_alpha) < 0.01:
                        score += 20
                        feedback.append(f"Correct overall alpha ({reported_alpha}).")
                    else:
                        feedback.append(f"Incorrect overall alpha. Reported: {reported_alpha}, Expected: {ground_truth_alpha:.3f}.")
                except ValueError:
                    feedback.append("Line 1 (Alpha) is not a number.")

                # Line 2: Max Dropped Alpha
                try:
                    reported_max_alpha = float(lines[1])
                    if abs(reported_max_alpha - target_alpha_val) < 0.01:
                        score += 20
                        feedback.append(f"Correct 'if dropped' alpha ({reported_max_alpha}).")
                    else:
                        feedback.append(f"Incorrect 'if dropped' alpha. Reported: {reported_max_alpha}, Expected: {target_alpha_val:.3f}.")
                except ValueError:
                    feedback.append("Line 2 (Max Alpha) is not a number.")

                # Line 3: Item Name
                reported_item = lines[2].strip().replace('"', '').replace("'", "")
                # Normalize check
                if reported_item.lower() == target_item_name.lower():
                    score += 20
                    feedback.append(f"Correct item identified ({reported_item}).")
                else:
                    feedback.append(f"Incorrect item identified. Reported: {reported_item}, Expected: {target_item_name}.")
            else:
                feedback.append(f"Report parsing error: {error}")

        # ---------------------------------------------------------------------
        # Verify OMV Configuration (20 pts)
        # ---------------------------------------------------------------------
        # Jamovi .omv files are ZIPs. Inside is a metadata.json or Analysis definition.
        # We want to check if Reliability analysis was run with A1 reversed.
        if "omv" in local_files and os.path.exists(local_files["omv"]):
            try:
                is_zip = zipfile.is_zipfile(local_files["omv"])
                if is_zip:
                    with zipfile.ZipFile(local_files["omv"], 'r') as z:
                        # Search for analysis files (usually in the root or an 'analyses' folder)
                        # We look for JSON files containing "reliability"
                        found_reliability = False
                        found_reverse = False
                        
                        for filename in z.namelist():
                            if filename.endswith(".json"):
                                try:
                                    content = z.read(filename).decode('utf-8')
                                    data = json.loads(content)
                                    
                                    # Jamovi analysis structure varies, but look for key indicators
                                    # "type": "reliability" or similar in 'analysis' objects
                                    
                                    # Check generic structure
                                    if isinstance(data, dict):
                                        # Looking for analysis type
                                        analysis_type = data.get("name", "") or data.get("type", "")
                                        if "reliability" in analysis_type.lower() or "scale" in analysis_type.lower():
                                            found_reliability = True
                                            
                                            # Check options
                                            options = data.get("options", {})
                                            
                                            # Check items
                                            items = options.get("vars", [])
                                            # or 'items'
                                            if not items: items = options.get("items", [])
                                            
                                            # Check reverse
                                            rev_items = options.get("revItems", [])
                                            if "A1" in rev_items:
                                                found_reverse = True
                                            
                                            # Also check if they computed a variable 'A1_r' and used that instead
                                            # If items contains a variable ending in '_r' or 'R', assume partial credit/valid approach
                                            for item in items:
                                                if "a1" in item.lower() and ("r" in item.lower() or "rev" in item.lower()):
                                                    found_reverse = True

                                except:
                                    pass
                        
                        if found_reliability:
                            score += 10
                            feedback.append("Reliability analysis found in project.")
                        else:
                            feedback.append("No Reliability analysis found in project file.")
                            
                        if found_reverse:
                            score += 10
                            feedback.append("Reverse coding configuration found.")
                        elif found_reliability:
                            feedback.append("Reverse coding for A1 NOT found in analysis settings.")
                            
            except Exception as e:
                feedback.append(f"Error inspecting OMV file: {e}")

    finally:
        # Cleanup
        import shutil
        shutil.rmtree(temp_dir)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }

if __name__ == "__main__":
    # Test stub
    pass