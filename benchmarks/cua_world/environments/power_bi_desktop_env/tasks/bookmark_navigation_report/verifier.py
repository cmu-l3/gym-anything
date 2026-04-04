#!/usr/bin/env python3
"""
Verifier for bookmark_navigation_report task.

Scoring Criteria (100 points total):
1. File Saved & Valid (10 pts): .pbix exists, >50KB, created during task.
2. Page Structure (20 pts): 3 specific pages ("Home", "Regional Revenue", "Category Breakdown").
3. Buttons Implemented (20 pts): At least 3 button visuals found (navigation structure).
4. Bookmarks Created (20 pts): Specific bookmarks "Revenue View" and "Category View".
5. Visuals Configured (30 pts): Clustered Column on Regional, Pie/Donut on Category.
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory for shared utilities if needed
# sys.path.insert(0, str(Path(__file__).parent.parent))
# from vlm_utils import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bookmark_navigation_report(traj, env_info, task_info):
    """
    Verify the Power BI bookmark and navigation report.
    Uses file parsing results exported from the Windows environment.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        # Path where PowerShell script saved the result
        remote_path = "C:/Users/Docker/Desktop/bookmark_nav_result.json"
        copy_from_env(remote_path, temp_file.name)
        
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve/parse task result: {str(e)}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Criteria
    score = 0
    feedback = []
    details = {}

    # --- Criterion 1: File Status (10 pts) ---
    file_exists = result.get("file_exists", False)
    file_size = result.get("file_size_bytes", 0)
    created_during = result.get("file_created_during_task", True) # Default to true if missing to avoid false fail on glitch

    if file_exists and file_size > 50000: # 50KB minimum for a real report
        if created_during:
            score += 10
            feedback.append("✅ File saved and valid.")
        else:
            score += 5
            feedback.append("⚠️ File exists but timestamp check failed (pre-existing?).")
    else:
        feedback.append("❌ Navigation_Report.pbix missing or empty.")
        # If file missing, stop here
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # --- Criterion 2: Page Structure (20 pts) ---
    # Expected: "Home", "Regional Revenue", "Category Breakdown"
    # Normalize to lowercase for comparison
    found_pages = [p.lower().strip() for p in result.get("page_names", [])]
    required_pages = ["home", "regional revenue", "category breakdown"]
    
    missing_pages = [p for p in required_pages if p not in found_pages]
    
    if not missing_pages:
        score += 20
        feedback.append("✅ All 3 pages created with correct names.")
    elif len(missing_pages) < 3:
        # Partial credit if at least some pages match
        score += 10
        feedback.append(f"⚠️ Partial pages found. Missing: {', '.join(missing_pages)}.")
    else:
        feedback.append("❌ Required page names not found.")

    # --- Criterion 3: Buttons (20 pts) ---
    # We expect 2 on Home + 1 on Regional + 1 on Category = 4 total, but logic asks for "at least 3"
    button_count = result.get("button_count", 0)
    
    if button_count >= 3:
        score += 20
        feedback.append(f"✅ Navigation buttons detected ({button_count} found).")
    elif button_count >= 1:
        score += 10
        feedback.append(f"⚠️ Few buttons found ({button_count}). Expected at least 3.")
    else:
        feedback.append("❌ No Button visuals found.")

    # --- Criterion 4: Bookmarks (20 pts) ---
    # Expected: "Revenue View", "Category View"
    found_bookmarks = [b.lower().strip() for b in result.get("bookmark_names", [])]
    required_bookmarks = ["revenue view", "category view"]
    
    missing_bms = [b for b in required_bookmarks if b not in found_bookmarks]
    
    if not missing_bms:
        score += 20
        feedback.append("✅ Both bookmarks ('Revenue View', 'Category View') found.")
    elif len(missing_bms) < 2:
        score += 10
        feedback.append(f"⚠️ One bookmark missing: {missing_bms[0]}.")
    else:
        feedback.append("❌ No required bookmarks found.")

    # --- Criterion 5: Visuals on Specific Pages (30 pts) ---
    vis_by_page = {k.lower().strip(): v for k, v in result.get("visual_types_by_page", {}).items()}
    
    # Check Regional Revenue: Clustered Column Chart
    # PBI ID: clusteredColumnChart
    reg_page_vis = vis_by_page.get("regional revenue", [])
    has_column_chart = any("clusteredcolumn" in v.lower() for v in reg_page_vis)
    
    # Check Category Breakdown: Pie or Donut
    # PBI ID: pieChart, donutChart
    cat_page_vis = vis_by_page.get("category breakdown", [])
    has_pie_donut = any(x in v.lower() for v in cat_page_vis for x in ["piechart", "donutchart"])
    
    if has_column_chart:
        score += 15
        feedback.append("✅ Clustered Column Chart found on Regional page.")
    else:
        feedback.append("❌ Missing Column Chart on Regional page.")
        
    if has_pie_donut:
        score += 15
        feedback.append("✅ Pie/Donut Chart found on Category page.")
    else:
        feedback.append("❌ Missing Pie/Donut Chart on Category page.")

    # Final Result
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }