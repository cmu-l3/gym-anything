#!/usr/bin/env python3
"""
Verifier for time_intelligence_yoy task.
Checks for PBIX file existence, correct page structure, visuals, and DAX measures.
"""

import json
import os
import zipfile
import shutil
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_pbix_metadata(pbix_path):
    """
    Extracts Layout JSON and searches DataModel binary from a .pbix file.
    PBIX files are ZIP archives containing 'Report/Layout' and 'DataModel'.
    """
    metadata = {
        "page_names": [],
        "visual_types": [],
        "model_strings": set(),
        "layout_found": False,
        "model_found": False
    }

    try:
        with zipfile.ZipFile(pbix_path, 'r') as z:
            # 1. Parse Report Layout (JSON)
            if 'Report/Layout' in z.namelist():
                metadata['layout_found'] = True
                with z.open('Report/Layout') as f:
                    # layout file is often UTF-16LE, sometimes UTF-8
                    content = f.read()
                    try:
                        layout_json = json.loads(content.decode('utf-16-le'))
                    except:
                        try:
                            layout_json = json.loads(content.decode('utf-8'))
                        except:
                            layout_json = {}
                    
                    # Extract pages and visuals
                    for section in layout_json.get('sections', []):
                        metadata['page_names'].append(section.get('displayName', ''))
                        
                        for container in section.get('visualContainers', []):
                            config_str = container.get('config', '{}')
                            try:
                                config = json.loads(config_str)
                                visual_type = config.get('singleVisual', {}).get('visualType', '')
                                if visual_type:
                                    metadata['visual_types'].append(visual_type)
                            except:
                                pass

            # 2. Scan DataModel (Binary) for strings
            # This is a heuristic. The DataModel is an Analysis Services backup.
            # Names of measures and DAX functions usually appear as UTF-16 or UTF-8 strings.
            if 'DataModel' in z.namelist():
                metadata['model_found'] = True
                with z.open('DataModel') as f:
                    binary_content = f.read()
                    
                    # Extract readable strings (approximate)
                    # Look for wide chars (UTF-16LE) often used in PBI internals
                    try:
                        # Decode blindly as latin-1 to preserve bytes, then regex search
                        text = binary_content.decode('latin-1') 
                        # We also search for UTF-16 patterns. 
                        # A simple way for verification is to search for byte sequences of keywords
                        
                        # Helper to add found strings to set
                        def add_if_found(keyword):
                            # Search ASCII/UTF-8
                            if keyword.encode('utf-8') in binary_content:
                                metadata['model_strings'].add(keyword)
                            # Search UTF-16LE
                            if keyword.encode('utf-16-le') in binary_content:
                                metadata['model_strings'].add(keyword)
                                
                        keywords = [
                            "DateTable", "CALENDAR", "CALENDARAUTO",
                            "YTD_Sales", "TOTALYTD",
                            "PY_Sales", "SAMEPERIODLASTYEAR", "DATEADD",
                            "YoY_Growth_Pct", "DIVIDE"
                        ]
                        
                        for k in keywords:
                            add_if_found(k)
                            
                    except Exception as e:
                        logger.warning(f"Error scanning DataModel: {e}")

    except Exception as e:
        logger.error(f"Error unzipping PBIX: {e}")

    return metadata

def verify_time_intelligence_yoy(traj, env_info, task_info):
    """
    Verifies the YoY Sales Analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy functionality not available"}

    # Define paths
    remote_json_path = "C:\\Users\\Docker\\Desktop\\yoy_result.json"
    remote_pbix_path = "C:\\Users\\Docker\\Desktop\\YoY_Sales_Analysis.pbix"
    
    # Temp directory for processing
    with tempfile.TemporaryDirectory() as temp_dir:
        local_json_path = os.path.join(temp_dir, "result.json")
        local_pbix_path = os.path.join(temp_dir, "analysis.pbix")
        
        # 1. Retrieve basic result JSON
        try:
            copy_from_env(remote_json_path, local_json_path)
            with open(local_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result metadata: {e}"}

        # 2. Retrieve PBIX file for deep inspection
        pbix_downloaded = False
        if result_data.get('file_exists'):
            try:
                copy_from_env(remote_pbix_path, local_pbix_path)
                pbix_downloaded = True
            except Exception as e:
                logger.warning(f"PBIX exists but failed to download: {e}")

        # --- SCORING CRITERIA ---
        score = 0
        feedback = []
        passed = False
        
        # Criterion 1: File Creation (10 pts)
        if result_data.get('file_created_during_task'):
            score += 10
            feedback.append("✅ Report saved during task")
        elif result_data.get('file_exists'):
            score += 5
            feedback.append("⚠️ Report exists but timestamp inconclusive")
        else:
            feedback.append("❌ Report file not found")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

        # Analyze PBIX if available
        meta = {"model_strings": set(), "page_names": [], "visual_types": []}
        if pbix_downloaded:
            meta = extract_pbix_metadata(local_pbix_path)

        # Criterion 2: Page Name (5 pts)
        # Check for "Sales Trend" (case insensitive)
        page_names_lower = [p.lower() for p in meta['page_names']]
        if "sales trend" in page_names_lower:
            score += 5
            feedback.append("✅ Page named 'Sales Trend'")
        else:
            feedback.append(f"❌ Page 'Sales Trend' not found (Found: {meta['page_names']})")

        # Criterion 3: Visuals (25 pts)
        # Expect: lineChart, card, pivotTable (Matrix)
        visuals = meta['visual_types']
        v_score = 0
        if "lineChart" in visuals: v_score += 10
        if "card" in visuals: v_score += 5
        if "pivotTable" in visuals or "matrix" in visuals: v_score += 10
        
        score += v_score
        if v_score == 25:
            feedback.append("✅ All required visuals present")
        else:
            feedback.append(f"⚠️ Some visuals missing. Found: {list(set(visuals))}")

        # Criterion 4: DAX Measures & Data Model (60 pts)
        # We check for the presence of specific strings in the DataModel binary
        strings = meta['model_strings']
        dax_score = 0
        
        # Date Table (15 pts)
        if "DateTable" in strings and ("CALENDAR" in strings or "CALENDARAUTO" in strings):
            dax_score += 15
            feedback.append("✅ DateTable created with DAX")
        else:
            feedback.append("❌ DateTable or CALENDAR function not detected")

        # YTD Measure (15 pts)
        if "YTD_Sales" in strings and "TOTALYTD" in strings:
            dax_score += 15
            feedback.append("✅ YTD_Sales measure correct")
        else:
            feedback.append("❌ YTD_Sales or TOTALYTD missing")

        # PY Measure (15 pts)
        if "PY_Sales" in strings and ("SAMEPERIODLASTYEAR" in strings or "DATEADD" in strings):
            dax_score += 15
            feedback.append("✅ PY_Sales measure correct")
        else:
            feedback.append("❌ PY_Sales or Time Intelligence function missing")

        # Growth Measure (15 pts)
        if "YoY_Growth_Pct" in strings and "DIVIDE" in strings:
            dax_score += 15
            feedback.append("✅ YoY_Growth_Pct measure correct")
        else:
            feedback.append("❌ YoY_Growth_Pct or DIVIDE missing")

        score += dax_score

        # Final check
        if score >= 65:
            passed = True
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }