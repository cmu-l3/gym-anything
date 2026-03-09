#!/usr/bin/env python3
"""
Verifier for shipping_geo_analysis task.

Requirements:
1. File Shipping_Analysis.pbix exists and created during task.
2. Calculated Column `Delivery_Days` exists (DATEDIFF logic implication).
3. Measure `Avg_Delivery_Days` exists.
4. Visuals:
   - Map (filledMap, map, or shapeMap)
   - Stacked Area Chart (areaChart, stackedAreaChart)
   - Funnel Chart (funnel)

Total Points: 100
Threshold: 70
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_shipping_geo_analysis(traj, env_info, task_info):
    """
    Verify the shipping analysis report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Fatal: copy_from_env not available"}

    # 1. Retrieve Result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        # The Windows path in the VM is C:\Users\Docker\Desktop\shipping_geo_result.json
        # The environment uses forward slashes for the copy function usually
        copy_from_env("C:/Users/Docker/Desktop/shipping_geo_result.json", temp_file.name)
        
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Error reading result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not verify task: Result file missing or unreadable. Error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass

    # 2. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence & Validity (15 pts)
    if result.get('file_exists') and result.get('file_created_after_start'):
        # Check size to ensure not empty
        if result.get('file_size_bytes', 0) > 5000:
            score += 15
            feedback_parts.append("✅ File saved and modified correctly")
        else:
            score += 5
            feedback_parts.append("⚠️ File exists but seems empty")
    else:
        feedback_parts.append("❌ File not found or not modified during task")
        return {"passed": False, "score": 0, "feedback": "Task Failed: Report file not found."}

    # Criterion 2: Calculated Column 'Delivery_Days' (20 pts)
    found_strings = result.get('model_strings_found', [])
    layout_dump = result.get('full_layout_search', '')
    
    has_delivery_days = "Delivery_Days" in found_strings
    if has_delivery_days:
        score += 20
        feedback_parts.append("✅ 'Delivery_Days' calculated column found")
    else:
        feedback_parts.append("❌ 'Delivery_Days' calculation not found")

    # Criterion 3: Measure 'Avg_Delivery_Days' (15 pts)
    has_avg_measure = "Avg_Delivery_Days" in found_strings
    if has_avg_measure:
        score += 15
        feedback_parts.append("✅ 'Avg_Delivery_Days' measure found")
    else:
        feedback_parts.append("❌ 'Avg_Delivery_Days' measure not found")

    # Criterion 4: Visuals
    # Get visual types from both the specific list and a broad search for robustness
    visual_types = set(result.get('visual_types', []))
    
    # Map Visual (20 pts)
    map_types = {'map', 'filledMap', 'shapeMap', 'azureMap'}
    if visual_types.intersection(map_types) or ('"map"' in layout_dump or '"filledMap"' in layout_dump):
        score += 20
        feedback_parts.append("✅ Map visual present")
    else:
        feedback_parts.append("❌ Map visual missing")

    # Stacked Area Chart (15 pts)
    area_types = {'areaChart', 'stackedAreaChart'}
    if visual_types.intersection(area_types) or ('"areaChart"' in layout_dump or '"stackedAreaChart"' in layout_dump):
        score += 15
        feedback_parts.append("✅ Stacked Area Chart present")
    else:
        feedback_parts.append("❌ Stacked Area Chart missing")

    # Funnel Chart (15 pts)
    funnel_types = {'funnel'}
    if visual_types.intersection(funnel_types) or '"funnel"' in layout_dump:
        score += 15
        feedback_parts.append("✅ Funnel Chart present")
    else:
        feedback_parts.append("❌ Funnel Chart missing")

    # 3. Final Evaluation
    passed = score >= 70
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }