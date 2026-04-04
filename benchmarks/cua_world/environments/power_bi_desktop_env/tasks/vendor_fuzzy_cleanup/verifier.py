#!/usr/bin/env python3
"""
Verifier for vendor_fuzzy_cleanup task.

Scoring (100 points total):
1. PBIX File Saved (10 pts)
2. CSV Exported (10 pts)
3. Fuzzy Matching Accuracy (40 pts) - Checks if messy vendor names were aggregated correctly.
4. Measure Accuracy (20 pts) - Checks if Spend_Share_Pct is calculated correctly.
5. Internal Implementation Checks (20 pts) - Checks for measure and fuzzy usage.
"""

import json
import os
import tempfile
import pandas as pd
import logging
import math

logger = logging.getLogger(__name__)

def verify_vendor_fuzzy_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function not available"}

    # Define paths
    remote_json_path = "C:/Users/Docker/Desktop/task_result.json"
    remote_csv_path = "C:/Users/Docker/Desktop/consolidated_spend.csv"
    
    # Ground Truth Data (Expected Sums)
    ground_truth = task_info.get('metadata', {}).get('ground_truth', {
        "TechSource Solutions": 2500,
        "Global Logistics Inc": 2500,
        "Apex Office Supplies": 1000,
        "BrightStar Energy": 2000,
        "Omega Marketing Group": 4000
    })
    total_expected_spend = sum(ground_truth.values()) # 12000

    # Temp files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    temp_json.close()
    temp_csv.close()

    try:
        # Copy files
        copy_from_env(remote_json_path, temp_json.name)
        
        # Try copying CSV only if JSON indicates it might exist, or just try anyway
        try:
            copy_from_env(remote_csv_path, temp_csv.name)
            csv_downloaded = True
        except Exception:
            csv_downloaded = False

        # Load JSON result
        with open(temp_json.name, 'r') as f:
            res_data = json.load(f)

        score = 0
        feedback = []

        # 1. PBIX File Saved (10 pts)
        if res_data.get('pbix_exists') and res_data.get('file_created_after_start'):
            score += 10
            feedback.append("PBIX file saved successfully.")
        else:
            feedback.append("PBIX file not found or not created during task.")

        # 2. CSV Exported (10 pts)
        if csv_downloaded and res_data.get('csv_exists'):
            score += 10
            feedback.append("CSV exported successfully.")
        else:
            feedback.append("CSV export not found.")

        # 3. Fuzzy Matching Accuracy (40 pts)
        fuzzy_score = 0
        if csv_downloaded:
            try:
                df = pd.read_csv(temp_csv.name)
                # Normalize column names
                df.columns = [c.strip() for c in df.columns]
                
                # Check for Vendor column (handle agent naming variations)
                vendor_col = next((c for c in df.columns if 'Vendor' in c), None)
                amount_col = next((c for c in df.columns if 'Amount' in c), None)

                if vendor_col and amount_col:
                    # Clean data: remove currency symbols, convert to float
                    df[amount_col] = df[amount_col].replace(r'[$,]', '', regex=True).astype(float)
                    
                    # Group by vendor to handle cases where agent didn't aggregate in visual?
                    # The task asked for a Table visual, which naturally aggregates if Amount is Sum.
                    # But if they put InvoiceID in the table, it wouldn't.
                    # We group here to be safe, but we expect the rows to be unique per vendor.
                    grouped = df.groupby(vendor_col)[amount_col].sum()
                    
                    matches = 0
                    total_items = len(ground_truth)
                    
                    for vendor, expected_amt in ground_truth.items():
                        # Fuzzy check on vendor name in CSV (e.g. agent might have typo)
                        # We look for the exact expected string first
                        if vendor in grouped.index:
                            actual = grouped[vendor]
                        else:
                            # Try to find partial match
                            found_vendor = next((v for v in grouped.index if vendor in str(v)), None)
                            actual = grouped[found_vendor] if found_vendor else 0
                        
                        if abs(actual - expected_amt) < 1.0:
                            matches += 1
                        else:
                            feedback.append(f"Mismatch for {vendor}: Expected {expected_amt}, Got {actual}")

                    if matches == total_items:
                        fuzzy_score = 40
                        feedback.append("All vendor totals match ground truth (Fuzzy Merge successful).")
                    elif matches >= 3:
                        fuzzy_score = 25
                        feedback.append(f"Partial match on vendors ({matches}/{total_items}).")
                    else:
                        fuzzy_score = 10 # Data present but mapping likely failed
                        feedback.append(f"Significant data mismatch ({matches}/{total_items} vendors correct). Fuzzy merge likely failed.")
                else:
                    feedback.append("Could not identify Vendor or Amount columns in CSV.")
            except Exception as e:
                feedback.append(f"Error analyzing CSV data: {str(e)}")
        
        score += fuzzy_score

        # 4. Measure Accuracy (20 pts)
        measure_score = 0
        if csv_downloaded:
            try:
                # Look for percentage column
                pct_col = next((c for c in df.columns if 'Share' in c or 'Pct' in c or '%' in c), None)
                if pct_col:
                    # Check first non-zero row
                    sample = df[df[pct_col].notnull()].iloc[0]
                    vendor_val = sample[vendor_col]
                    amount_val = sample[amount_col]
                    pct_val = float(str(sample[pct_col]).replace('%', ''))
                    
                    # Allow 0-1 scale or 0-100 scale
                    if pct_val < 1.0: 
                        pct_val *= 100
                    
                    expected_pct = (amount_val / total_expected_spend) * 100
                    if abs(pct_val - expected_pct) < 1.0:
                        measure_score = 20
                        feedback.append("Spend_Share_Pct calculation verified.")
                    else:
                        measure_score = 5
                        feedback.append(f"Spend_Share_Pct seems incorrect. Expected ~{expected_pct:.1f}%, Got {pct_val:.1f}%")
                else:
                    feedback.append("Spend_Share_Pct column missing from export.")
            except Exception:
                pass # Already logged error above
        
        score += measure_score

        # 5. Internal Implementation Checks (20 pts)
        internal_score = 0
        if res_data.get('measure_found_in_model'):
            internal_score += 10
            feedback.append("Measure definition found in Data Model.")
        
        if res_data.get('fuzzy_found_in_mashup'):
            internal_score += 10
            feedback.append("Fuzzy logic found in Data Mashup.")
        elif fuzzy_score == 40:
            # If they got the right answer, we give points even if we missed the 'Fuzzy' string
            internal_score += 10
            feedback.append("Output correct implies fuzzy logic used (keyword check skipped).")
            
        score += internal_score

        return {
            "passed": score >= 70,
            "score": score,
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"System Error: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.remove(temp_json.name)
        if os.path.exists(temp_csv.name):
            os.remove(temp_csv.name)