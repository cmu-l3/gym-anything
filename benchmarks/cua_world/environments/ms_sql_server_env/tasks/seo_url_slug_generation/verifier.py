#!/usr/bin/env python3
"""
Verifier for seo_url_slug_generation task.
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_seo_url_slug_generation(traj, env_info, task_info):
    """
    Verify the SEO slug generation task.
    
    Criteria:
    1. Function dbo.fn_CreateSlug exists (10)
    2. Function works correctly (Test case: lowercase, no special chars, hyphens) (20)
    3. View Production.vw_ProductSEO exists (10)
    4. View has correct dependency on function (10)
    5. View logic correct for standard product (Category/Subcategory/Name-ID) (20)
    6. View logic correct for NULL subcategory (uncategorized/general) (10)
    7. Export file exists and contains correct JSON data (20)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Function Existence (10)
    if result.get("function_exists"):
        score += 10
        feedback_parts.append("Function created.")
    else:
        feedback_parts.append("Function dbo.fn_CreateSlug missing.")

    # 2. Function Logic (20)
    # Test Input: "Test & Value / 123 + 456"
    # Expected: "test-value-123-456" (approximately)
    fn_out = result.get("function_test_result", "").strip()
    # Check for lowercase
    is_lower = fn_out == fn_out.lower() if fn_out else False
    # Check for removal of special chars (&, /, +)
    clean_chars = not any(c in fn_out for c in ['&', '/', '+', ',', '.'])
    # Check for hyphens
    has_hyphens = '-' in fn_out
    
    if is_lower and clean_chars and has_hyphens and "test" in fn_out:
        score += 20
        feedback_parts.append(f"Function logic verified ('{fn_out}').")
    elif fn_out:
        score += 10
        feedback_parts.append(f"Function logic partial credit ('{fn_out}').")
    else:
        feedback_parts.append("Function logic test failed.")

    # 3. View Existence (10)
    if result.get("view_exists"):
        score += 10
        feedback_parts.append("View created.")
    else:
        feedback_parts.append("View Production.vw_ProductSEO missing.")

    # 4. View Dependency (10) - Anti-gaming
    if result.get("view_dependency"):
        score += 10
        feedback_parts.append("View correctly uses the function.")
    else:
        feedback_parts.append("View does not use the function (possible hardcoding or manual logic).")

    # 5. Standard Path Logic (20)
    # Expected: bikes/mountain-bikes/mountain-100-silver-38-771
    path_771 = result.get("sample_path_771", "").strip()
    # Regex to validate format: category/subcategory/product-id
    # Allow some variation in sanitization but structure must match
    if re.match(r'^[a-z0-9-]+/[a-z0-9-]+/[a-z0-9-]+-771$', path_771):
        score += 20
        feedback_parts.append(f"Standard URL path correct ({path_771}).")
    elif path_771:
        # Check if ID is at end at least
        if path_771.endswith("771"):
            score += 10
            feedback_parts.append(f"Standard URL path format issue, but ID present ({path_771}).")
        else:
            feedback_parts.append(f"Standard URL path incorrect ({path_771}).")
    else:
        feedback_parts.append("Standard URL path missing.")

    # 6. Null Handling Logic (10)
    # Expected: uncategorized/general/adjustable-race-1
    path_1 = result.get("sample_path_1", "").strip()
    if "uncategorized" in path_1 and "general" in path_1 and path_1.endswith("-1"):
        score += 10
        feedback_parts.append("NULL category/subcategory handling correct.")
    elif path_1:
         feedback_parts.append(f"NULL handling incorrect ({path_1}).")
    else:
         feedback_parts.append("NULL handling check failed.")

    # 7. File Verification (20)
    if result.get("file_exists"):
        content = result.get("file_content", "")
        # Check if it looks like JSON and contains the slug
        if "771" in str(content) and "mountain" in str(content).lower():
            score += 20
            feedback_parts.append("Export file valid.")
        else:
            score += 10
            feedback_parts.append("Export file exists but content mismatch.")
    else:
        feedback_parts.append("Export file missing.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }