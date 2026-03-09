#!/usr/bin/env python3
"""
Verifier for graduated_color_choropleth task.

Verification Strategy:
1. Check if output project file exists and was created during task.
2. Unzip the project file (.gvsproj is a ZIP archive).
3. Analyze XML content for:
    - Interval/Graduated symbology type
    - POP_EST classification field
    - 5 classes configured
    - Distinct colors used
"""

import json
import os
import sys
import tempfile
import zipfile
import re
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_graduated_color_choropleth(traj, env_info, task_info):
    """
    Verify the gvSIG project contains a graduated color map on POP_EST.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('output_path', "/home/ga/gvsig_data/projects/population_choropleth.gvsproj")
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check basic file existence and anti-gaming (20 points)
    if not result_data.get('output_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Project file not found. Did you save to the correct path?"
        }
    
    if not result_data.get('file_created_during_task', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Project file exists but matches pre-task state. You must save a new version."
        }
    
    score += 20
    feedback_parts.append("Valid project file created")

    # 3. Retrieve and Analyze Project File
    temp_proj = tempfile.NamedTemporaryFile(delete=False, suffix='.gvsproj')
    extract_dir = tempfile.mkdtemp()
    
    try:
        # Copy project file from container
        copy_from_env(expected_output_path, temp_proj.name)
        
        # Unzip project file
        try:
            with zipfile.ZipFile(temp_proj.name, 'r') as zip_ref:
                zip_ref.extractall(extract_dir)
            
            # Combine all text/xml content for analysis
            # gvSIG stores layout and View definitions in XML files inside the zip
            combined_content = ""
            for root, dirs, files in os.walk(extract_dir):
                for file in files:
                    if file.endswith('.xml') or file.endswith('.gvp') or file.endswith('.state'):
                        try:
                            with open(os.path.join(root, file), 'r', errors='ignore') as f:
                                combined_content += f.read() + "\n"
                        except:
                            pass
            
            # CRITERION 1: Symbology Type (25 points)
            # Look for indicators of interval/graduated symbology
            interval_keywords = [
                "vectorialIntervalLegend", "IntervalLegend", "GraduatedColor", 
                "intervals", "classified", "ranges"
            ]
            has_interval = any(kw.lower() in combined_content.lower() for kw in interval_keywords)
            
            if has_interval:
                score += 25
                feedback_parts.append("Interval symbology detected")
            else:
                feedback_parts.append("Interval symbology NOT detected")
            
            # CRITERION 2: Classification Field (20 points)
            # Look for POP_EST field reference
            if "POP_EST" in combined_content or "pop_est" in combined_content:
                score += 20
                feedback_parts.append("Correct classification field (POP_EST)")
            else:
                # Partial credit for population related field
                if "POPULATION" in combined_content.upper() or "POP" in combined_content.upper():
                    score += 10
                    feedback_parts.append("Incorrect field, but likely population-related")
                else:
                    feedback_parts.append("POP_EST field not found in project")

            # CRITERION 3: Class Count (20 points)
            # Estimate number of classes by counting symbol/interval definitions
            # This relies on finding repeated XML tags typical of legend definitions
            matches_symbol = len(re.findall(r'<symbol\s+', combined_content, re.IGNORECASE))
            matches_interval = len(re.findall(r'<interval\s+', combined_content, re.IGNORECASE))
            matches_range = len(re.findall(r'<range\s+', combined_content, re.IGNORECASE))
            
            # Use the max count found
            count = max(matches_symbol, matches_interval, matches_range)
            
            # If explicit count is mentioned in XML
            if re.search(r'numIntervals.*5', combined_content, re.IGNORECASE) or \
               re.search(r'intervals.*5', combined_content, re.IGNORECASE):
                count = 5
            
            if count == 5:
                score += 20
                feedback_parts.append("Correct number of classes (5)")
            elif 4 <= count <= 6:
                score += 10
                feedback_parts.append(f"Class count close to target (found ~{count})")
            elif count > 0:
                score += 5
                feedback_parts.append(f"Classes defined, but count mismatch (found ~{count})")
            else:
                feedback_parts.append("Could not verify class count")

            # CRITERION 4: Distinct Colors (15 points)
            # Extract hex or rgb colors
            hex_colors = set(re.findall(r'#[0-9a-fA-F]{6}', combined_content))
            rgb_colors = set(re.findall(r'rgb\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*\)', combined_content, re.IGNORECASE))
            
            distinct_colors = len(hex_colors) + len(rgb_colors)
            
            if distinct_colors >= 4:
                score += 15
                feedback_parts.append("Distinct colors applied")
            elif distinct_colors >= 2:
                score += 8
                feedback_parts.append("Some color variation detected")
            else:
                feedback_parts.append("Colors appear uniform (single symbol?)")

        except zipfile.BadZipFile:
            return {"passed": False, "score": 20, "feedback": "Project file is not a valid ZIP archive"}
            
    except Exception as e:
        logger.error(f"Error analyzing project file: {e}")
        feedback_parts.append("Error analyzing project content")
    finally:
        if os.path.exists(temp_proj.name):
            os.unlink(temp_proj.name)
        if os.path.exists(extract_dir):
            shutil.rmtree(extract_dir)

    # Final Evaluation
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }