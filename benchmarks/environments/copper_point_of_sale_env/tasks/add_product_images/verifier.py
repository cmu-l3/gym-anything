#!/usr/bin/env python3
"""
Verifier for add_product_images task (Copper POS).
Verifies that items were created with correct images by inspecting the exported CSV.
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_product_images(traj, env_info, task_info):
    """
    Verify the agent created items with assigned images.
    
    Strategy:
    1. Check if the CSV export exists and was created during the task.
    2. Parse the CSV to find the 3 required items.
    3. Verify the 'Image' or 'Photo' column for those items matches the expected filenames.
    4. VLM Trajectory: Verify file picker interaction (secondary).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_items = metadata.get('expected_items', [])
    output_csv_path = metadata.get('output_csv_path', r"C:\Users\Docker\Documents\inventory_update_verification.csv")
    
    # Temporary files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        # 1. Retrieve Result JSON
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        if not result_data.get('output_csv_exists'):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Exported CSV file not found. Did you export the inventory to 'inventory_update_verification.csv'?"
            }
            
        if not result_data.get('output_created_during_task'):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "The CSV file appears to be old. Please export a fresh CSV."
            }

        # 2. Retrieve CSV File
        copy_from_env(output_csv_path, temp_csv.name)
        
        # 3. Parse CSV
        # Copper CSV exports typically have headers. We need to find columns for 'Item' and 'Image'/'Description'
        found_items = {}
        
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            # Normalize headers (Copper headers might vary slightly by version)
            headers = [h.lower() for h in reader.fieldnames] if reader.fieldnames else []
            
            # Identify key columns
            name_col = next((h for h in reader.fieldnames if 'item' in h.lower() or 'name' in h.lower()), None)
            image_col = next((h for h in reader.fieldnames if 'image' in h.lower() or 'photo' in h.lower() or 'picture' in h.lower()), None)
            
            if not name_col:
                return {"passed": False, "score": 20, "feedback": "CSV exported but could not identify 'Item Name' column."}
                
            # Iterate rows
            for row in reader:
                item_name = row[name_col].strip()
                # Find if this row matches one of our targets
                for target in expected_items:
                    if target['name'].lower() == item_name.lower():
                        image_val = row.get(image_col, "") if image_col else ""
                        found_items[target['name']] = image_val
        
        # 4. Scoring
        score = 20 # Base points for successful export
        feedback_parts = ["CSV exported successfully."]
        
        items_correct = 0
        for target in expected_items:
            t_name = target['name']
            t_img = target['image_file']
            
            if t_name in found_items:
                actual_img = found_items[t_name]
                # Check if the expected filename is in the image path (handling full paths)
                if t_img.lower() in actual_img.lower():
                    score += 20
                    items_correct += 1
                    feedback_parts.append(f"✓ {t_name}: Image assigned correctly.")
                elif actual_img:
                    # Item exists but wrong image
                    score += 5
                    feedback_parts.append(f"⚠ {t_name}: Item found but image '{actual_img}' does not match '{t_img}'.")
                else:
                    # Item exists but no image
                    score += 5
                    feedback_parts.append(f"⚠ {t_name}: Item found but no image assigned.")
            else:
                feedback_parts.append(f"✗ {t_name}: Item not found in export.")
                
        # VLM check for file picker interaction (bonus/verification)
        # In a real scenario, we would add VLM logic here. 
        # For this implementation, we assume CSV proof is sufficient for the core score.
        score += 10 if items_correct > 0 else 0 # Bonus for at least one success implying workflow knowledge
        
        passed = (items_correct >= 2) # Pass if at least 2/3 items are correct
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed due to system error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)