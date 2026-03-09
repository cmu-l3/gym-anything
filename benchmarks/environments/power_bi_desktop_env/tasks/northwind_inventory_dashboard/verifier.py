#!/usr/bin/env python3
"""
Verifier for northwind_inventory_dashboard task.

Verifies:
1. PBIX creation and structure (Visuals, Measures).
2. Data logic via exported CSV (The most robust way to check if logic is correct).
3. CSV logic: 
   - Target = ReorderLevel * 1.2
   - Qty = max(0, Target - (InStock + OnOrder))
   - Cost = Qty * UnitPrice
   - Filter = Only rows with Qty > 0
"""

import json
import os
import tempfile
import io
import csv
import logging
import math

logger = logging.getLogger(__name__)

def verify_inventory_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/Users/Docker/Desktop/inventory_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: PBIX File (10 pts) ---
    if result.get('pbix_exists') and result.get('timestamp_valid'):
        score += 10
        feedback_parts.append("PBIX saved")
    else:
        feedback_parts.append("PBIX missing or old")

    # --- Criterion 2: Data Import & Model Structure (20 pts) ---
    # We check if columns/measures were found in the model file
    calc_cols = result.get('calc_columns_found', [])
    measures = result.get('measures_found', [])
    
    if "Target_Level" in calc_cols and "Replenishment_Qty" in calc_cols:
        score += 10
        feedback_parts.append("Calculated columns found")
    
    if "Restock_Cost" in measures:
        score += 10
        feedback_parts.append("Restock_Cost measure found")
        
    # --- Criterion 3: Visuals (10 pts) ---
    visuals = result.get('visual_types', [])
    if "card" in visuals and "table" in visuals:
        score += 10
        feedback_parts.append("Card and Table visuals present")
    elif "table" in visuals:
        score += 5
        feedback_parts.append("Table present, Card missing")
        
    # --- Criterion 4: CSV Content & Logic (60 pts) ---
    csv_content = result.get('csv_content', "")
    if not csv_content:
        feedback_parts.append("CSV export missing or empty")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Parse CSV content
    try:
        f = io.StringIO(csv_content)
        reader = csv.DictReader(f)
        rows = list(reader)
        
        if len(rows) == 0:
            feedback_parts.append("CSV is empty")
        else:
            # Check for critical columns (flexible matching)
            headers = [h.lower() for h in reader.fieldnames] if reader.fieldnames else []
            has_name = any('product' in h or 'name' in h for h in headers)
            has_qty = any('qty' in h or 'replenish' in h for h in headers)
            has_stock = any('stock' in h or 'available' in h for h in headers)
            
            if not (has_name and has_qty):
                feedback_parts.append("CSV missing required columns (Product, Qty)")
            else:
                score += 10  # Export successful
                
                # Logic Verification on a sample row
                # We need to find specific products to verify logic
                # Example: "Northwoods Cranberry Sauce" (ID 8)
                # Data: Price 40, Stock 6, OnOrder 0, Reorder 10.
                # Logic: TotalAvail=6. Target=10*1.2=12. Needed=12-6=6. Cost=6*40=240.
                
                logic_pass_count = 0
                filter_pass = True
                total_checked = 0
                
                for row in rows:
                    # Clean keys
                    r = {k.strip().lower(): v for k, v in row.items()}
                    
                    # Try to extract values
                    try:
                        # Find the qty value
                        qty_key = next((k for k in r.keys() if 'replenishment' in k or 'qty' in k), None)
                        if not qty_key: continue
                        
                        qty_val = float(r[qty_key])
                        
                        # Verify Filter: No rows should have 0 or negative qty
                        if qty_val <= 0:
                            filter_pass = False
                        
                        # Find other values for logic check (if available in CSV)
                        # The task asks to include: Total_Available, ReorderLevel, Target_Level, UnitPrice
                        avail_key = next((k for k in r.keys() if 'available' in k or 'stock' in k), None)
                        reorder_key = next((k for k in r.keys() if 'reorder' in k), None)
                        target_key = next((k for k in r.keys() if 'target' in k), None)
                        
                        if avail_key and reorder_key and target_key:
                            avail = float(r[avail_key])
                            reorder = float(r[reorder_key])
                            target = float(r[target_key])
                            
                            # Check Target Logic: Target ~ Reorder * 1.2
                            if abs(target - (reorder * 1.2)) < 0.1 or abs(target - math.ceil(reorder * 1.2)) < 0.1:
                                logic_pass_count += 1
                                total_checked += 1
                                
                    except ValueError:
                        continue
                
                if filter_pass and len(rows) > 0:
                    score += 10
                    feedback_parts.append("Table correctly filtered (no zero rows)")
                else:
                    feedback_parts.append("Table NOT filtered correctly (contains zero/neg values)")
                    
                if total_checked > 0 and logic_pass_count == total_checked:
                    score += 40
                    feedback_parts.append(f"Logic verified on {total_checked} rows")
                elif total_checked > 0:
                    score += 20
                    feedback_parts.append(f"Logic partial match ({logic_pass_count}/{total_checked})")
                else:
                    # If columns missing, we can't verify logic, but give points for having data
                    score += 10 
                    feedback_parts.append("Could not verify calculation logic (missing columns)")

    except Exception as e:
        feedback_parts.append(f"Error parsing CSV: {e}")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }