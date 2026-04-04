#!/usr/bin/env python3
"""
Verifier for create_sales_dashboard_mockup task.

Verifies:
1. .eddx source file exists, is a valid ZIP/XML structure, and was created during task.
2. .png export exists and is a valid image.
3. Content Analysis: Parses the .eddx (ZIP) to find XML content matching specific 
   KPI values and titles required by the task description.
"""

import os
import json
import tempfile
import zipfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_sales_dashboard_mockup(traj, env_info, task_info):
    """
    Verify the sales dashboard creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON exported from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Source File (.eddx) Existence & Timestamp (20 pts)
    if result.get('eddx_exists') and result.get('eddx_created_during_task'):
        score += 20
        feedback_parts.append(".eddx file created successfully")
    elif result.get('eddx_exists'):
        score += 10
        feedback_parts.append(".eddx file exists but timestamp is old (reused file?)")
    else:
        feedback_parts.append(".eddx file NOT found")

    # 2. Check Export File (.png) Existence (10 pts)
    if result.get('png_exists') and result.get('png_size_bytes', 0) > 10000:
        score += 10
        feedback_parts.append(".png export created successfully")
    else:
        feedback_parts.append(".png export missing or too small")

    # 3. Content Verification (Deep Inspection of .eddx) (70 pts)
    # We download the .eddx file and inspect its internal XML
    content_score = 0
    content_feedback = []
    
    if result.get('eddx_exists'):
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Documents/sales_dashboard.eddx", temp_eddx.name)
            
            # .eddx files are ZIP archives containing XML
            if zipfile.is_zipfile(temp_eddx.name):
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    # Extract all text content from all XML files in the archive
                    full_text_content = ""
                    for filename in zf.namelist():
                        if filename.endswith(".xml"):
                            try:
                                full_text_content += zf.read(filename).decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Required strings from task description
                    required_items = [
                        ("Executive Sales", 10),     # Title
                        ("4,250,000", 10),           # Revenue KPI
                        ("68%", 10),                 # Margin KPI
                        ("142", 10),                 # Customer KPI
                        ("29,500", 10),              # Deal Size KPI
                        ("Revenue by Region", 10),   # Bar Chart Title
                        ("SaaS Platform", 10)        # Donut Chart Label
                    ]
                    
                    for text, pts in required_items:
                        # Simple substring search in the raw XML
                        # EdrawMax stores text in <Text>...</Text> or similar tags, 
                        # so the raw string should be present
                        if text in full_text_content:
                            content_score += pts
                            content_feedback.append(f"Found '{text}'")
                        else:
                            content_feedback.append(f"Missing '{text}'")
            else:
                feedback_parts.append("File is not a valid EdrawMax archive")
                
        except Exception as e:
            feedback_parts.append(f"Error parsing .eddx file: {str(e)}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    
    score += content_score
    if content_feedback:
        feedback_parts.append("Content Check: " + ", ".join(content_feedback))

    # Final Calculation
    passed = score >= 70  # Requires files + significant content match
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }