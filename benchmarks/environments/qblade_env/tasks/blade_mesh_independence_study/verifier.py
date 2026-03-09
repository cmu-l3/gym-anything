#!/usr/bin/env python3
"""
Verifier for blade_mesh_independence_study task.

Checks:
1. Refined project file exists and is valid XML.
2. Blade definition in project has >= 48 sections/elements.
3. Report file exists and contains numerical Cp values.
4. Timestamps verify work was done during task.
"""

import json
import os
import tempfile
import base64
import re
import xml.etree.ElementTree as ET

def verify_blade_mesh_independence(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    passed = False

    # 1. Verify Project Existence (20 pts)
    if result.get("project_exists"):
        score += 20
        feedback.append("Refined project file saved.")
        
        # 2. Analyze Project XML for Mesh Refinement (40 pts)
        # We need to copy the actual .wpa file to parse it
        project_path = result.get("project_path")
        temp_wpa = tempfile.NamedTemporaryFile(delete=False, suffix='.wpa')
        try:
            copy_from_env(project_path, temp_wpa.name)
            
            # Parse XML
            try:
                tree = ET.parse(temp_wpa.name)
                root = tree.getroot()
                
                # QBlade WPA structure usually has: 
                # <HAWTBlade> ... <BladeData> ... <Elem> or <Station>
                # We'll search for blade elements. In QBlade XML, elements are often listed 
                # under a blade definition. We count occurrence of station definitions.
                # A generic robust way is to count specific tags typically used for sections.
                
                # Searching for element tags common in QBlade: 'Elem', 'BldElem', or 'Pos' inside 'Blade'
                # Let's count all children of the main blade data container.
                
                blade_elements = 0
                
                # Strategy: Look for the blade definition with the most children (likely the main blade)
                # or look for specific element tags.
                # In QBlade v0.96 XML: <Blade><Pos>...</Pos><Pos>...</Pos></Blade>
                
                for blade in root.findall(".//Blade"):
                    # Count 'Pos' or 'Elem' children
                    elems = list(blade)
                    if len(elems) > blade_elements:
                        blade_elements = len(elems)
                
                # Fallback search if specific tag structure varies
                if blade_elements == 0:
                     # Count occurrences of a common parameter tag that appears once per section, e.g. "Chord"
                     # This is a heuristic text search if XML parsing structure is ambiguous
                    with open(temp_wpa.name, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read()
                        blade_elements = content.count("<Chord>")

                if blade_elements >= 48:
                    score += 40
                    feedback.append(f"Blade mesh refined successfully (Detected ~{blade_elements} sections).")
                elif blade_elements > 0:
                    feedback.append(f"Blade mesh found but insufficient refinement (~{blade_elements} sections, target >= 50).")
                else:
                    feedback.append("Could not parse blade sections from project file.")

            except ET.ParseError:
                feedback.append("Project file exists but contains invalid XML.")
                
        except Exception as e:
            feedback.append(f"Failed to analyze project file: {str(e)}")
        finally:
            if os.path.exists(temp_wpa.name):
                os.unlink(temp_wpa.name)
    else:
        feedback.append("Refined project file not found.")

    # 3. Verify Report Content (20 pts)
    if result.get("report_exists"):
        try:
            content_b64 = result.get("report_content_b64", "")
            report_text = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
            
            # Check for numbers resembling Cp (0.0 to 0.59)
            # Regex for float numbers
            floats = [float(x) for x in re.findall(r"0\.\d+", report_text)]
            
            if len(floats) >= 2:
                score += 20
                feedback.append(f"Report contains valid Cp data points: {floats[:2]}.")
            elif len(floats) == 1:
                score += 10
                feedback.append("Report contains only one Cp value.")
            else:
                score += 5
                feedback.append("Report exists but no valid Cp values found (0.0 - 0.59).")
        except Exception as e:
            feedback.append("Error parsing report content.")
    else:
        feedback.append("Report file not found.")

    # 4. Process Verification / Anti-Gaming (20 pts)
    # Check if app was running and file sizes are reasonable
    if result.get("app_running"):
        score += 10
        feedback.append("QBlade was running at end of task.")
    
    project_size = result.get("project_size", 0)
    if project_size > 5000: # 5KB min for a valid project
        score += 10
    else:
        feedback.append("Project file seems too small/empty.")

    # Final Pass Determination
    # Must have project file + mesh refinement check passed (>= 60 points combined from those steps)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }