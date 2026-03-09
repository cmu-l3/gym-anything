#!/usr/bin/env python3
"""
Verifier for usda_nutrition_research task.

Verifies:
1. JSON file existence and validity.
2. Content accuracy (7 specific foods with plausible nutrient values).
3. Browser evidence (History visits and Bookmarks).
"""

import json
import os
import base64
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected plausible ranges per 100g
# Format: "nutrient": (min, max)
EXPECTED_RANGES = {
    "chicken_breast": {
        "calories": (100, 180), "protein_g": (18, 35), "fat_g": (1, 10), "carbs_g": (0, 2), "fiber_g": (0, 1)
    },
    "brown_rice": {
        "calories": (100, 140), "protein_g": (2, 4), "fat_g": (0.5, 2), "carbs_g": (20, 30), "fiber_g": (1, 3)
    },
    "broccoli": {
        "calories": (25, 45), "protein_g": (2, 4), "fat_g": (0, 1), "carbs_g": (4, 10), "fiber_g": (2, 4)
    },
    "salmon": {
        "calories": (120, 260), "protein_g": (18, 27), "fat_g": (5, 18), "carbs_g": (0, 2), "fiber_g": (0, 1)
    },
    "sweet_potato": {
        "calories": (75, 110), "protein_g": (1, 3), "fat_g": (0, 1), "carbs_g": (15, 25), "fiber_g": (2, 5)
    },
    "greek_yogurt": {
        "calories": (50, 80), "protein_g": (8, 12), "fat_g": (0, 1), "carbs_g": (2, 6), "fiber_g": (0, 1)
    },
    "almonds": {
        "calories": (550, 650), "protein_g": (18, 25), "fat_g": (45, 55), "carbs_g": (15, 25), "fiber_g": (10, 15)
    }
}

REQUIRED_FOODS = list(EXPECTED_RANGES.keys())
REQUIRED_FIELDS = ["calories", "protein_g", "fat_g", "carbs_g", "fiber_g"]

def verify_usda_nutrition_research(traj, env_info, task_info):
    """
    Verify the USDA nutrition research task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # ------------------------------------------------------------------
    # Criterion 1: JSON File Existence & Validity (15 pts)
    # ------------------------------------------------------------------
    file_content = None
    if result.get("file_exists") and result.get("file_fresh"):
        try:
            raw_content = base64.b64decode(result.get("file_content_b64", "")).decode('utf-8')
            file_content = json.loads(raw_content)
            score += 15
            feedback.append("JSON file exists, is fresh, and valid.")
        except json.JSONDecodeError:
            feedback.append("JSON file exists but is invalid JSON.")
            score += 5 # Partial credit for creating file
    elif result.get("file_exists"):
        feedback.append("JSON file exists but was not modified during task.")
    else:
        feedback.append("JSON file not found.")

    # ------------------------------------------------------------------
    # Criterion 2: Data Content Validation (45 pts)
    # ------------------------------------------------------------------
    if file_content:
        foods_found = 0
        data_correct = 0
        
        # Normalize keys for leniency (e.g., "Chicken Breast" -> "chicken_breast")
        normalized_content = {}
        for k, v in file_content.items():
            norm_k = k.lower().replace(" ", "_")
            normalized_content[norm_k] = v

        for food_key in REQUIRED_FOODS:
            # Check if food exists (flexible matching)
            found_key = None
            if food_key in normalized_content:
                found_key = food_key
            else:
                # Try partial match
                for k in normalized_content:
                    if food_key.split('_')[0] in k: # e.g. 'chicken' in 'chicken_meat'
                        found_key = k
                        break
            
            if found_key:
                foods_found += 1
                food_data = normalized_content[found_key]
                
                # Check fields and values
                food_valid = True
                for field in REQUIRED_FIELDS:
                    val = food_data.get(field)
                    
                    # Convert string numbers to float if necessary
                    if isinstance(val, str):
                        try:
                            val = float(val)
                        except ValueError:
                            val = None
                            
                    if val is None or not isinstance(val, (int, float)):
                        food_valid = False
                        break
                        
                    # Check range
                    min_v, max_v = EXPECTED_RANGES[food_key][field]
                    if not (min_v * 0.8 <= val <= max_v * 1.2): # 20% tolerance on top of range
                        # Special case for fiber/carbs where 0 is acceptable if min is low
                        if min_v < 1 and val < 1:
                            pass
                        else:
                            food_valid = False
                            break
                
                if food_valid:
                    data_correct += 1
        
        # Scoring Content
        # 10 pts for having keys for all 7 foods
        if foods_found >= 7:
            score += 10
            feedback.append("All 7 required foods found in JSON.")
        elif foods_found >= 4:
            score += 5
            feedback.append(f"Found {foods_found}/7 required foods.")
        else:
            feedback.append(f"Only found {foods_found}/7 required foods.")

        # 35 pts for data accuracy (5 pts per correctly populated food)
        score += (data_correct * 5)
        if data_correct == 7:
            feedback.append("Nutritional data is plausible for all foods.")
        else:
            feedback.append(f"Nutritional data valid for {data_correct}/7 foods.")

    # ------------------------------------------------------------------
    # Criterion 3: Browser History (15 pts)
    # ------------------------------------------------------------------
    history_visits = result.get("history_visits", 0)
    if history_visits >= 5:
        score += 15
        feedback.append(f"Evidence of FDC research found ({history_visits} visits).")
    elif history_visits >= 1:
        score += 5
        feedback.append(f"Minimal evidence of FDC research ({history_visits} visits).")
    else:
        feedback.append("No history of visiting FoodData Central found.")

    # ------------------------------------------------------------------
    # Criterion 4: Bookmarks (25 pts)
    # ------------------------------------------------------------------
    folder_exists = result.get("bookmark_folder_exists", False)
    bm_count = result.get("bookmark_count", 0)

    if folder_exists:
        score += 10
        feedback.append("'Nutrition Research' bookmark folder exists.")
        
        if bm_count >= 5:
            score += 15
            feedback.append(f"Found {bm_count} bookmarks to USDA database.")
        elif bm_count >= 1:
            score += 5
            feedback.append(f"Found only {bm_count} bookmarks (expected 5+).")
        else:
            feedback.append("No USDA bookmarks found in the folder.")
    else:
        feedback.append("'Nutrition Research' bookmark folder not found.")

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = (score >= 60) and (foods_found >= 5) # Hard requirement on JSON content
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }