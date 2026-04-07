#!/usr/bin/env python3
"""
Verifier for Oracle Analytics Desktop task: Configure Logical Sort Order.

Verification Strategy:
1. File Verification (40 pts):
   - Check if 'LogicalSort_Fulfillment.dva' exists.
   - Verify it was created during the task.
   - Inspect the internal structure (DVA is a zip) for 'Same Day', 'First Class', etc.

2. VLM Verification (60 pts):
   - Trajectory Analysis: Did the agent set a custom sort?
   - Final Screen Analysis: Are the bars visually ordered correctly?
     (Same Day -> First Class -> Second Class -> Standard Class)

Anti-Gaming:
- File modification time check.
- Visual confirmation of the specific order which is NOT alphabetical.
"""

import json
import os
import zipfile
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_logical_sort_order(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """Verify the logical sort order task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_path', r"C:\Users\Docker\Documents\LogicalSort_Fulfillment.dva")
    expected_order = metadata.get('required_sort_order', ["Same Day", "First Class", "Second Class", "Standard Class"])
    
    # --------------------------------------------------------------------------
    # Step 1: File Verification
    # --------------------------------------------------------------------------
    score = 0
    feedback_parts = []
    
    # Get result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(r"C:\Users\Docker\Documents\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        result = {}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("Workbook saved successfully")
        if created_during:
            score += 10
            feedback_parts.append("File created during task session")
        else:
            feedback_parts.append("File timestamp indicates pre-existing file (potential gaming)")
    else:
        feedback_parts.append("Workbook file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --------------------------------------------------------------------------
    # Step 2: Content Verification (Deep Inspection of DVA)
    # --------------------------------------------------------------------------
    # DVA files are ZIPs containing XML/JSON definitions. 
    # We look for the sort strings in proximity to verify they were used in definition.
    dva_content_score = 0
    temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    try:
        copy_from_env(expected_path, temp_dva.name)
        
        with zipfile.ZipFile(temp_dva.name, 'r') as z:
            # Search for xml or json files that define the view
            found_order_strings = 0
            file_list = z.namelist()
            
            # Aggregate text content from relevant files
            full_text = ""
            for fname in file_list:
                if fname.endswith('.xml') or fname.endswith('.json') or fname.endswith('.txt'):
                    try:
                        with z.open(fname) as f:
                            content = f.read().decode('utf-8', errors='ignore')
                            full_text += content
                    except:
                        pass
            
            # Check for the sort terms presence
            # This is a weak check (they exist in data anyway), but we look for them being part of the file
            # A stronger check would be VLM, so we keep this minimal.
            if all(term in full_text for term in expected_order):
                dva_content_score = 10
                feedback_parts.append("Sort terms found in project metadata")
            
            score += dva_content_score
            
    except Exception as e:
        logger.warning(f"Failed to inspect DVA content: {e}")
        feedback_parts.append("Could not verify internal file structure")
    finally:
        if os.path.exists(temp_dva.name):
            os.unlink(temp_dva.name)

    # --------------------------------------------------------------------------
    # Step 3: VLM Visual Verification (CRITICAL)
    # --------------------------------------------------------------------------
    # We need to verify the VISUAL ORDER on the chart.
    # Alphabetical: First Class, Same Day, Second Class, Standard Class
    # Logical:      Same Day, First Class, Second Class, Standard Class
    
    from gym_anything.vlm import get_final_screenshot, query_vlm
    
    final_img = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_img:
        prompt = f"""
        Analyze this chart created in Oracle Analytics Desktop.
        Goal: Verify if the 'Ship Mode' bars are sorted logically by speed, NOT alphabetically.
        
        Expected Logical Order (Fastest to Slowest):
        1. Same Day
        2. First Class
        3. Second Class
        4. Standard Class
        
        Alphabetical Order (Incorrect):
        - First Class
        - Same Day
        - Second Class
        - Standard Class
        
        Check 1: Can you see a bar chart?
        Check 2: Read the labels on the axis. What is the order?
        Check 3: Does the order match the 'Expected Logical Order'?
        Check 4: Is the title 'Revenue by Service Level' visible?
        
        Respond in JSON:
        {{
            "is_bar_chart": true/false,
            "observed_order": ["first label", "second label", ...],
            "matches_logical_order": true/false,
            "title_correct": true/false,
            "reasoning": "..."
        }}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, image=final_img)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('is_bar_chart'):
                vlm_score += 20
                
            if parsed.get('matches_logical_order'):
                vlm_score += 40
                feedback_parts.append("Visual verification passed: Correct logical sort order detected")
            else:
                obs_order = parsed.get('observed_order', [])
                feedback_parts.append(f"Visual verification failed: Observed order {obs_order}")
                
            if parsed.get('title_correct'):
                vlm_score += 10
                
        except Exception as e:
            logger.error(f"VLM query failed: {e}")
            feedback_parts.append("Visual verification failed due to error")
    else:
        feedback_parts.append("No final screenshot available for visual verification")

    # Normalize score
    # Max possible: 20 (file) + 10 (content) + 70 (VLM) = 100
    # Adjusted weights:
    # File: 20
    # Content: 10
    # VLM: 70 (20 chart + 40 order + 10 title)
    
    total_score = score + vlm_score
    passed = total_score >= 70 and created_during
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }