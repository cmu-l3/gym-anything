#!/usr/bin/env python3
"""
Verifier for analyze_2d_mesh_properties task.
Compares agent's extracted text/CSV data against ground truth generated from the HDF file.
"""

import json
import os
import re
import tempfile
import csv
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_2d_mesh_properties(traj, env_info, task_info):
    """
    Verify the HEC-RAS 2D mesh analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    report_path = metadata.get('report_path', "/home/ga/Documents/hec_ras_results/mesh_analysis_report.txt")
    csv_path = metadata.get('csv_path', "/home/ga/Documents/hec_ras_results/mesh_cell_data.csv")

    score = 0
    max_score = 100
    feedback_parts = []
    
    # -------------------------------------------------------------------------
    # Retrieve Files from Environment
    # -------------------------------------------------------------------------
    files = {}
    for remote_path, local_key in [
        ("/tmp/task_result.json", "meta"),
        ("/tmp/ground_truth.json", "gt"),
        (report_path, "report"),
        (csv_path, "csv")
    ]:
        temp_file = tempfile.NamedTemporaryFile(delete=False)
        temp_file.close()
        try:
            copy_from_env(remote_path, temp_file.name)
            files[local_key] = temp_file.name
        except Exception:
            files[local_key] = None

    # -------------------------------------------------------------------------
    # Load Ground Truth and Metadata
    # -------------------------------------------------------------------------
    try:
        with open(files["meta"], 'r') as f:
            meta = json.load(f)
        with open(files["gt"], 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Critical verification error: failed to load result metadata or ground truth ({str(e)})."
        }
    finally:
        # Cleanup JSON files
        for key in ["meta", "gt"]:
            if files.get(key) and os.path.exists(files[key]):
                os.unlink(files[key])

    if not gt.get("success"):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Ground truth generation failed: {gt.get('error', 'unknown error')}. HDF file might be missing or corrupt."
        }

    # -------------------------------------------------------------------------
    # CHECK 1: File Existence and Freshness (10 points)
    # -------------------------------------------------------------------------
    files_ok_score = 0
    if meta.get("report_exists") and meta.get("report_fresh"):
        files_ok_score += 5
    if meta.get("csv_exists") and meta.get("csv_fresh"):
        files_ok_score += 5
    
    score += files_ok_score
    if files_ok_score < 10:
        feedback_parts.append(f"Files missing or not created during task ({files_ok_score}/10 pts)")
    else:
        feedback_parts.append("All output files created successfully")

    # -------------------------------------------------------------------------
    # CHECK 2: Report Content Analysis (50 points)
    # -------------------------------------------------------------------------
    report_score = 0
    report_text = ""
    
    if files["report"]:
        try:
            with open(files["report"], 'r') as f:
                report_text = f.read()
            os.unlink(files["report"])
        except:
            pass

    if report_text:
        # Helper to find numbers in text
        def find_num(text, targets, tolerance=0.1, is_int=False):
            # Find all numbers
            nums = [float(x) for x in re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", text)]
            for target in targets:
                found = False
                for n in nums:
                    if is_int:
                        if abs(n - target) < 0.1: found = True
                    else:
                        # Use relative error for large numbers, absolute for small
                        if abs(target) > 1e-6:
                            if abs(n - target) / abs(target) < tolerance: found = True
                        else:
                            if abs(n - target) < tolerance: found = True
                    if found: break
                if not found: return False
            return True

        # A. Total Cell Count (10 pts)
        if find_num(report_text, [gt["total_cells"]], is_int=True):
            report_score += 10
            feedback_parts.append("Report: Total cell count correct")
        else:
            feedback_parts.append(f"Report: Total cell count mismatch (expected {gt['total_cells']})")

        # B. Flow Area Names (5 pts)
        names_found = 0
        for name in gt["area_names"]:
            if name.lower() in report_text.lower():
                names_found += 1
        if names_found == len(gt["area_names"]):
            report_score += 5
        else:
            feedback_parts.append(f"Report: Missing flow area names ({names_found}/{len(gt['area_names'])})")

        # C. Statistics per Area (35 pts)
        # We check one area (usually there is only one in Muncie example)
        stats_score = 0
        max_stats_score = 35
        for area_name, data in gt["flow_areas"].items():
            area_stats_correct = 0
            # 1. Min Elev
            if find_num(report_text, [data["elev_min"]], tolerance=0.01): area_stats_correct += 1
            # 2. Max Elev
            if find_num(report_text, [data["elev_max"]], tolerance=0.01): area_stats_correct += 1
            # 3. Mean Elev
            if find_num(report_text, [data["elev_mean"]], tolerance=0.05): area_stats_correct += 1
            # 4. Std Dev
            if find_num(report_text, [data["elev_std"]], tolerance=0.1): area_stats_correct += 1
            # 5. Extents (min X, max X, min Y, max Y)
            if find_num(report_text, [data["x_min"], data["x_max"], data["y_min"], data["y_max"]], tolerance=0.01): area_stats_correct += 3
            
            # Normalize to 35 points
            # Total checks: 1+1+1+1+3 = 7 items
            stats_score += (area_stats_correct / 7) * max_stats_score
            break # Just check the first/main area to avoid double counting if multiple
        
        report_score += int(stats_score)
        feedback_parts.append(f"Report: Statistics accuracy {int(stats_score)}/35")

    else:
        feedback_parts.append("Report: File empty or unreadable")

    score += report_score

    # -------------------------------------------------------------------------
    # CHECK 3: CSV Data Verification (40 points)
    # -------------------------------------------------------------------------
    csv_score = 0
    csv_rows = []
    
    if files["csv"]:
        try:
            with open(files["csv"], 'r') as f:
                reader = csv.DictReader(f)
                headers = [h.strip().lower() for h in reader.fieldnames] if reader.fieldnames else []
                # Normalize headers
                # Looking for: area_name, cell_index, center_x, center_y, min_elevation
                
                # Check headers (5 pts)
                required = ["area", "index", "x", "y", "elev"]
                header_match = sum(1 for r in required if any(r in h for h in headers))
                if header_match >= 4:
                    csv_score += 5
                
                for row in reader:
                    # Normalize keys
                    clean_row = {}
                    for k, v in row.items():
                        kl = k.lower()
                        if "area" in kl: clean_row["area"] = v
                        elif "index" in kl or "id" == kl: clean_row["index"] = v
                        elif "x" in kl: clean_row["x"] = v
                        elif "y" in kl: clean_row["y"] = v
                        elif "elev" in kl: clean_row["elev"] = v
                    csv_rows.append(clean_row)
            os.unlink(files["csv"])
        except Exception as e:
            feedback_parts.append(f"CSV: Parse error {str(e)}")

    if csv_rows:
        # A. Row Count (10 pts)
        if abs(len(csv_rows) - gt["total_cells"]) < 2:
            csv_score += 10
            feedback_parts.append("CSV: Row count correct")
        else:
            feedback_parts.append(f"CSV: Row count mismatch ({len(csv_rows)} vs {gt['total_cells']})")

        # B. Spot Check Values (25 pts)
        # Use samples from ground truth
        matches = 0
        checks = 0
        
        # Build a quick lookup for CSV data to avoid O(N^2)
        # Key: (area, index) -> row
        csv_lookup = {}
        for row in csv_rows:
            try:
                # Default area name if missing/empty
                area = row.get("area", "").strip()
                if not area and len(gt["area_names"]) == 1:
                    area = gt["area_names"][0]
                    
                idx = int(float(row.get("index", -1)))
                csv_lookup[(area, idx)] = row
            except:
                pass

        for area_name, data in gt["flow_areas"].items():
            for sample in data.get("samples", []):
                checks += 1
                s_idx = sample["index"]
                
                # Try exact match
                row = csv_lookup.get((area_name, s_idx))
                # If not found, try fuzzy match on just index if only 1 area
                if not row and len(gt["flow_areas"]) == 1:
                    # Try finding index in the first few rows just in case user didn't put area name
                    pass

                if row:
                    try:
                        # Check coords and elevation
                        x = float(row.get("x", 0))
                        y = float(row.get("y", 0))
                        elev = float(row.get("elev", 0))
                        
                        if (abs(x - sample["x"]) < 1.0 and 
                            abs(y - sample["y"]) < 1.0 and 
                            abs(elev - sample["elev"]) < 0.05):
                            matches += 1
                    except:
                        pass
        
        if checks > 0:
            accuracy = matches / checks
            points = int(accuracy * 25)
            csv_score += points
            feedback_parts.append(f"CSV: Data accuracy {matches}/{checks} samples correct")
        else:
            feedback_parts.append("CSV: Could not perform spot checks")

    score += csv_score

    # -------------------------------------------------------------------------
    # Final Scoring
    # -------------------------------------------------------------------------
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }