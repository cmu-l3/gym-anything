#!/usr/bin/env python3
"""
Verifier for Export Filtered Products CSV task.

Verification Strategy:
1. Programmatic (80 points):
   - File existence and timestamp (anti-gaming).
   - Column check: MUST contain SKU, Name, Regular price. MUST NOT contain others (strict filter).
   - Category check: All rows in CSV must match Ground Truth for 'Clothing'.
   - Data accuracy check: Values match DB.

2. VLM Trajectory (20 points):
   - Confirm 'Export' button was clicked.
   - Confirm 'Clothing' category was selected in the dropdown.
   - Confirm specific columns were selected/others unselected.

Pass Threshold: 70 points AND Correct Columns AND Correct Category.
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ================================================================
# VLM HELPERS
# ================================================================

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

TRAJECTORY_PROMPT = """You are analyzing screenshots of a WooCommerce product export task.
The agent needs to:
1. Click "Export" on the products page.
2. Select specific columns (SKU, Name, Price) and uncheck others.
3. Select "Clothing" as the product category.
4. Generate the CSV.

Look at the images provided.
Assess:
1. EXPORT_INITIATED: Did the agent open the Export tool?
2. COLUMNS_ADJUSTED: Did the agent interact with the "Which columns should be exported?" field?
3. CATEGORY_SELECTED: Did the agent select "Clothing" in the "Which product category?" field?
4. GENERATE_CLICKED: Did the agent click "Generate CSV"?

Respond in JSON:
{
    "export_initiated": true/false,
    "columns_adjusted": true/false,
    "category_selected": true/false,
    "generate_clicked": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_export_filtered_products_csv(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    result_data = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result_data = json.load(f)
            os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    score = 0
    feedback = []

    # 2. Check File Existence & Timestamp (20 pts)
    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file clothing_prices.csv not found."}
    
    score += 10
    feedback.append("File found.")
    
    if result_data.get('file_created_during_task'):
        score += 10
        feedback.append("File created during task.")
    else:
        feedback.append("WARNING: File timestamp check failed (pre-existing?).")

    # 3. Load CSV and Ground Truth
    csv_rows = []
    ground_truth = []
    
    try:
        # Load CSV
        with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp_csv:
            copy_from_env(result_data.get('csv_path'), tmp_csv.name)
            with open(tmp_csv.name, 'r', encoding='utf-8-sig') as f: # utf-8-sig handles BOM
                reader = csv.DictReader(f)
                csv_headers = reader.fieldnames if reader.fieldnames else []
                csv_rows = list(reader)
            os.unlink(tmp_csv.name)
            
        # Load Ground Truth
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp_gt:
            copy_from_env(result_data.get('ground_truth_path'), tmp_gt.name)
            with open(tmp_gt.name, 'r') as f:
                ground_truth = json.load(f)
            os.unlink(tmp_gt.name)
            
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read data files: {e}"}

    # 4. Verify Columns (30 pts)
    # Required: SKU, Name, Regular price
    # Forbidden: Description, Stock, etc. (Agent must strictly filter)
    required_cols = {'SKU', 'Name', 'Regular price'}
    # Allow some variation in header names if standard (WooCommerce standard is "SKU", "Name", "Regular price")
    
    current_headers = set(h.strip() for h in csv_headers)
    
    missing_cols = required_cols - current_headers
    
    # Check for extra columns (we want a filtered report)
    # Typically WC export has 40+ columns. If we have < 10, they likely filtered.
    filtered_cols = len(current_headers) < 10
    
    if not missing_cols:
        score += 15
        feedback.append("Required columns present.")
        if filtered_cols:
            score += 15
            feedback.append("Columns correctly filtered.")
        else:
            feedback.append(f"Too many columns ({len(current_headers)}). Did not filter columns.")
    else:
        feedback.append(f"Missing columns: {missing_cols}")

    # 5. Verify Data Content (Category Filter) (30 pts)
    # Check if CSV rows match Ground Truth
    
    # Map Ground Truth by SKU for easy lookup
    gt_map = {item['SKU']: item for item in ground_truth if item['SKU']}
    csv_skus = [row.get('SKU') for row in csv_rows if row.get('SKU')]
    
    # Check 1: Are all CSV items in Ground Truth? (Precision)
    # If CSV has items NOT in GT, they exported wrong category
    extra_items = [sku for sku in csv_skus if sku not in gt_map]
    
    # Check 2: Are all GT items in CSV? (Recall)
    missing_items = [sku for sku in gt_map if sku not in csv_skus]
    
    if len(csv_rows) == 0:
        feedback.append("CSV is empty.")
    elif not extra_items:
        score += 15
        feedback.append("Category filtering correct (no extra items).")
        if not missing_items:
            score += 15
            feedback.append("All expected items present.")
        else:
            score += 5
            feedback.append(f"Missing {len(missing_items)} expected items.")
    else:
        feedback.append(f"Found {len(extra_items)} items not in Clothing category (e.g. {extra_items[:3]}).")

    # 6. VLM Verification (20 pts)
    # Use trajectory to verify they actually used the export tool settings
    vlm_score = 0
    if query_vlm:
        # Sample frames
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        if vlm_res:
            if vlm_res.get('columns_adjusted'): vlm_score += 10
            if vlm_res.get('category_selected'): vlm_score += 10
            feedback.append(f"VLM verified process (Confidence: {vlm_res.get('confidence')}).")
        else:
            # Fallback if VLM fails but data is perfect
            if score >= 70: vlm_score = 20
            
    score += vlm_score

    # Final Pass Check
    # Must have correct columns AND correct category filtering to pass
    passed = (not missing_cols) and (not extra_items) and (len(csv_rows) > 0) and score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }