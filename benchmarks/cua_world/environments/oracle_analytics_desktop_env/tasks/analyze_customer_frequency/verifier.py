#!/usr/bin/env python3
"""
Verifier for analyze_customer_frequency task (Oracle Analytics Desktop).

Verifies:
1. DVA workbook file existence and timestamp.
2. Workbook content (unzipping .dva) for:
   - Calculation "Orders Per Customer" with aggregation logic.
   - Usage as Attribute (Dimension).
   - Bar Chart presence.
3. VLM Trajectory analysis for workflow confirmation.
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customer_frequency(traj, env_info, task_info):
    """
    Verify the Customer Frequency Analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('expected_filename', 'Customer_Frequency_Dist.dva')
    
    # Initialize score
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Temp directory for processing
    with tempfile.TemporaryDirectory() as temp_dir:
        # ---------------------------------------------------------
        # 1. FILE VERIFICATION (from export_result.ps1 JSON)
        # ---------------------------------------------------------
        json_path = os.path.join(temp_dir, "task_result.json")
        try:
            # Note: The PS script saves to C:\workspace\task_result.json
            # mapped to /workspace/task_result.json in container? 
            # Or we copy from the absolute Windows path if copy_from_env supports it.
            # Assuming standard mapping:
            copy_from_env("C:\\workspace\\task_result.json", json_path)
            
            with open(json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}

        if not result_data.get("output_exists"):
            return {"passed": False, "score": 0, "feedback": "Workbook file not found."}
        
        score += 10
        feedback_parts.append("Workbook file exists")
        
        if result_data.get("file_created_during_task"):
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("File timestamp verification failed")

        if result_data.get("output_size_bytes", 0) > 5000: # 5KB min
            score += 10
        else:
            feedback_parts.append("File suspiciously small")

        # ---------------------------------------------------------
        # 2. CONTENT VERIFICATION (Deep Inspection of .dva)
        # ---------------------------------------------------------
        dva_local_path = os.path.join(temp_dir, expected_filename)
        try:
            copy_from_env(result_data["output_path"], dva_local_path)
            
            is_valid_dva = False
            has_calculation = False
            has_attribute_usage = False
            has_chart = False
            
            if zipfile.is_zipfile(dva_local_path):
                with zipfile.ZipFile(dva_local_path, 'r') as z:
                    file_list = z.namelist()
                    # Iterate through files to find XML/JSON definitions
                    # DVA structure typically contains datamodel and visual definitions
                    
                    content_text = ""
                    for f in file_list:
                        if f.endswith('.xml') or f.endswith('.json') or f.endswith('.txt'):
                            try:
                                content_text += z.read(f).decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Search for keywords in the project definition
                    # 1. Calculation Logic
                    if "Orders Per Customer" in content_text:
                        score += 10
                        feedback_parts.append("Calculated column found")
                        
                        # Check for aggregation keywords associated with the calculation
                        if "count" in content_text.lower() and "by" in content_text.lower():
                            score += 20
                            has_calculation = True
                            feedback_parts.append("LOD aggregation logic detected")
                    
                    # 2. Visualization
                    if "bar" in content_text.lower() or "chart" in content_text.lower():
                        score += 10
                        has_chart = True
                        
                    # 3. Attribute Semantics (harder to parse exactly, checking for dimension usage)
                    # Often represented as 'treatAs="attribute"' or usage in categorical axis
                    if "attribute" in content_text.lower():
                        score += 10
                        has_attribute_usage = True

            else:
                feedback_parts.append("Invalid DVA file format")

        except Exception as e:
            feedback_parts.append(f"Content inspection failed: {str(e)}")

        # ---------------------------------------------------------
        # 3. VLM TRAJECTORY VERIFICATION
        # ---------------------------------------------------------
        frames = sample_trajectory_frames(traj, n=4)
        
        vlm_prompt = """
        Analyze these screenshots of a user working in Oracle Analytics Desktop.
        Goal: Create a chart showing the distribution of "Orders Per Customer".
        
        Look for:
        1. A calculated column dialog showing a formula like "COUNT(...) BY (...)".
        2. Converting a measure to an attribute (e.g., clicking "Treat as Attribute").
        3. A bar chart where the X-axis (bottom) shows integer values (1, 2, 3...) representing order counts.
        4. The chart showing a distribution (histogram shape).
        
        Return JSON:
        {
            "calculation_editor_seen": boolean,
            "measure_to_attribute_seen": boolean,
            "distribution_chart_visible": boolean,
            "x_axis_is_integers": boolean
        }
        """
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_result and vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            if parsed.get('calculation_editor_seen'):
                score += 5
            if parsed.get('measure_to_attribute_seen'):
                score += 5
            if parsed.get('distribution_chart_visible'):
                score += 10
                feedback_parts.append("Visual confirmation of chart")
            if parsed.get('x_axis_is_integers'):
                score += 10
        else:
            feedback_parts.append("VLM verification skipped/failed")

    # Final Pass Determination
    # Must have file, calculation logic, and reasonable score
    passed = (score >= 70) and result_data.get("output_exists") and has_calculation
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }