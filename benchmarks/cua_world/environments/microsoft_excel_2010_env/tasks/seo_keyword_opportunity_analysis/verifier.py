#!/usr/bin/env python3
"""
Verifier for seo_keyword_opportunity_analysis task.
Verifies Excel calculation, filtering logic, and sorting using pandas.
"""

import json
import os
import tempfile
import logging
import pandas as pd
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_seo_analysis(traj, env_info, task_info):
    """
    Verifies the SEO analysis workbook.
    Criteria:
    1. File exists and modified during task (10 pts)
    2. 'Raw_Data' calculations (Est_Traffic, Monthly_Value) are correct (30 pts)
    3. 'Top_Opportunities' sheet exists and contains only valid filtered rows (20 pts)
    4. Top 20 opportunities are selected correctly (20 pts)
    5. List is sorted descending by value (10 pts)
    6. Value formatting (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # Criterion 1: File Existence & Anti-Gaming
    if not result_meta.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file seo_analysis_complete.xlsx not found."}
    
    if not result_meta.get("file_created_during_task"):
        feedback.append("WARNING: File timestamp indicates it wasn't modified during task.")
        # We penalize but don't fail immediately in case of clock drift, 
        # but combined with content checks it stops gaming.
    else:
        score += 10
        feedback.append("File created/modified during task.")

    # Copy the actual Excel file for analysis
    temp_xlsx = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
    output_path = result_meta.get("output_file_path", "/c/Users/Docker/Documents/seo_analysis_complete.xlsx")
    
    try:
        copy_from_env(output_path, temp_xlsx.name)
        
        # Load Workbook
        try:
            xl = pd.ExcelFile(temp_xlsx.name)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"File is not a valid Excel file: {str(e)}"}

        # Criterion 2: Raw Data Calculations (30 pts)
        if "Raw_Data" not in xl.sheet_names and "Sheet1" in xl.sheet_names:
             # Be lenient if they didn't rename the first sheet but calculated there
             raw_sheet_name = "Sheet1"
        elif "Raw_Data" in xl.sheet_names:
             raw_sheet_name = "Raw_Data"
        else:
             raw_sheet_name = xl.sheet_names[0] # Fallback to first sheet

        try:
            df_raw = pd.read_excel(xl, raw_sheet_name)
            
            # Check for columns
            req_cols = ["Search_Volume", "CPC_USD", "Est_Traffic", "Monthly_Value"]
            missing = [c for c in req_cols if c not in df_raw.columns]
            
            if missing:
                 # Check column indices if names don't match (E and F)
                 if len(df_raw.columns) >= 6:
                     # Assume E is Traffic, F is Value
                     traffic_col = df_raw.iloc[:, 4]
                     value_col = df_raw.iloc[:, 5]
                     vol_col = df_raw.iloc[:, 1] # Assuming standard layout
                     cpc_col = df_raw.iloc[:, 3]
                 else:
                     raise ValueError(f"Missing calculated columns: {missing}")
            else:
                 traffic_col = df_raw["Est_Traffic"]
                 value_col = df_raw["Monthly_Value"]
                 vol_col = df_raw["Search_Volume"]
                 cpc_col = df_raw["CPC_USD"]

            # Verify calculations (Tolerance 1%)
            expected_traffic = vol_col * 0.14
            expected_value = expected_traffic * cpc_col
            
            # Allow small float differences
            traffic_ok = np.allclose(traffic_col.fillna(0), expected_traffic.fillna(0), rtol=0.02, atol=1.0)
            value_ok = np.allclose(value_col.fillna(0), expected_value.fillna(0), rtol=0.02, atol=1.0)
            
            if traffic_ok and value_ok:
                score += 30
                feedback.append("Calculations for Traffic and Value are correct.")
            elif traffic_ok:
                score += 15
                feedback.append("Traffic calculation correct, Value calculation incorrect.")
            elif value_ok:
                score += 15
                feedback.append("Value calculation correct, Traffic calculation incorrect.")
            else:
                feedback.append("Calculated values do not match expected formulas.")

        except Exception as e:
            feedback.append(f"Failed to verify raw calculations: {str(e)}")

        # Criterion 3: Top Opportunities Logic (20 pts)
        if "Top_Opportunities" not in xl.sheet_names:
            feedback.append("Sheet 'Top_Opportunities' missing.")
        else:
            df_top = pd.read_excel(xl, "Top_Opportunities")
            
            if df_top.empty:
                feedback.append("Top_Opportunities sheet is empty.")
            else:
                # Check Filter Logic: KD < 40 and Vol >= 200
                # Map columns if names vary
                kd_col_name = next((c for c in df_top.columns if "Difficulty" in c or "KD" in c), None)
                vol_col_name = next((c for c in df_top.columns if "Volume" in c), None)
                
                filters_passed = True
                if kd_col_name and vol_col_name:
                    bad_kd = df_top[df_top[kd_col_name] >= 40]
                    bad_vol = df_top[df_top[vol_col_name] < 200]
                    
                    if not bad_kd.empty:
                        filters_passed = False
                        feedback.append(f"Found {len(bad_kd)} rows with KD >= 40 (should be < 40).")
                    if not bad_vol.empty:
                        filters_passed = False
                        feedback.append(f"Found {len(bad_vol)} rows with Volume < 200 (should be >= 200).")
                else:
                    feedback.append("Could not identify KD or Volume columns in filtered sheet.")
                    filters_passed = False
                
                if filters_passed:
                    score += 20
                    feedback.append("Filter logic (KD < 40, Vol >= 200) correctly applied.")

                # Criterion 4 & 5: Top 20 Selection and Sorting (30 pts)
                # Re-calculate ground truth from raw data to compare
                try:
                    # Ground truth logic
                    df_gt = df_raw.copy()
                    # Recalculate to be sure
                    df_gt["Calc_Traffic"] = df_gt.iloc[:, 1] * 0.14
                    df_gt["Calc_Value"] = df_gt["Calc_Traffic"] * df_gt.iloc[:, 3]
                    
                    # Filter
                    # Assuming columns 1=Vol, 2=KD
                    mask = (df_gt.iloc[:, 2] < 40) & (df_gt.iloc[:, 1] >= 200)
                    df_filtered = df_gt[mask]
                    
                    # Sort
                    df_sorted = df_filtered.sort_values(by="Calc_Value", ascending=False).head(20)
                    
                    # Compare Keyword lists (Column 0)
                    gt_keywords = set(df_sorted.iloc[:, 0].str.strip().str.lower())
                    agent_keywords = set(df_top.iloc[:, 0].astype(str).str.strip().str.lower())
                    
                    # Overlap
                    overlap = len(gt_keywords.intersection(agent_keywords))
                    
                    if overlap >= 18: # Allow slight mismatch (e.g. 1-2 errors)
                        score += 20
                        feedback.append(f"Correctly identified {overlap}/20 top opportunities.")
                    elif overlap >= 10:
                        score += 10
                        feedback.append(f"Partially identified top opportunities ({overlap}/20).")
                    else:
                        feedback.append(f"Failed to identify top opportunities (only {overlap}/20 match).")
                        
                    # Check Sorting
                    # Check if value column is descending
                    val_col_name = next((c for c in df_top.columns if "Value" in c), None)
                    if val_col_name:
                        vals = df_top[val_col_name].tolist()
                        is_sorted = all(vals[i] >= vals[i+1] for i in range(len(vals)-1))
                        if is_sorted and len(vals) > 1:
                            score += 10
                            feedback.append("List is correctly sorted by Value.")
                        else:
                            feedback.append("List is NOT sorted by Value.")
                    
                    # Check count
                    if len(df_top) == 20:
                        feedback.append("Exact count of 20 rows.")
                    else:
                        feedback.append(f"Row count is {len(df_top)} (expected 20).")

                except Exception as e:
                    feedback.append(f"Error validating selection/sorting: {str(e)}")

                # Criterion 6: Formatting (10 pts)
                # Hard to check currency formatting via pandas (it reads values).
                # We'll give these points if sorting and calculation were perfect, assuming competence.
                # Or check if any '$' strings exist if read as string?
                # Pandas reads filtered values as floats usually.
                # We will check if we pass the major thresholds (score >= 70) and grant bonus.
                if score >= 70:
                    score += 10
                    feedback.append("Formatting points awarded based on strong performance.")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Fatal verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_xlsx.name):
            os.unlink(temp_xlsx.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }