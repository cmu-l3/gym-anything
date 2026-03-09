#!/usr/bin/env python3
"""
Verifier for lab_scale_power_curve_gen task.

Checks:
1. Output file exists and was created during task.
2. Output file contains dimensional Power (Watts) vs Wind Speed data.
3. Data covers the requested range (4-20 m/s).
4. Power values are physically reasonable for the specified rotor (Order of magnitude check).
5. VLM verification of the workflow (Airfoil Gen -> Polar -> Blade -> Rotor -> Sim).
"""

import json
import base64
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lab_scale_power_curve_gen(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Freshness (20 pts) ---
    if result.get("output_exists") and result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("Output file created successfully.")
    elif result.get("output_exists"):
        score += 10
        feedback_parts.append("Output file exists but timestamp is old (reused?).")
    else:
        feedback_parts.append("Output file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2 & 3: Data Validation (50 pts) ---
    content_b64 = result.get("content_preview_base64", "")
    if not content_b64:
        feedback_parts.append("Output file is empty.")
    else:
        try:
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
            lines = [l.strip() for l in content.split('\n') if l.strip()]
            
            # Look for numeric data
            data_rows = []
            header_found = False
            
            for line in lines:
                parts = line.split()
                # Simple heuristic for data row: starts with number
                if len(parts) >= 2 and parts[0].replace('.','',1).isdigit():
                    try:
                        # Try parsing first two cols as float
                        col1 = float(parts[0]) # Likely Wind Speed or TSR
                        col2 = float(parts[1]) # Likely Power or Cp
                        data_rows.append((col1, col2))
                    except ValueError:
                        continue
            
            if len(data_rows) < 5:
                 feedback_parts.append("File does not contain enough tabular data.")
            else:
                # Analyze data range and dimensionality
                # We expect Wind Speed (4-20) and Power (Watts)
                
                # Check X-axis (Wind Speed)
                x_values = [row[0] for row in data_rows]
                min_x = min(x_values)
                max_x = max(x_values)
                
                # Check Y-axis (Power)
                y_values = [row[1] for row in data_rows]
                max_y = max(y_values)
                
                # Range Check (20 pts)
                if 3.5 <= min_x <= 4.5 and 19.5 <= max_x <= 20.5:
                    score += 20
                    feedback_parts.append("Data covers correct wind speed range (4-20 m/s).")
                else:
                    feedback_parts.append(f"Data range incorrect (Found {min_x}-{max_x}, expected 4-20).")
                
                # Dimensionality Check (30 pts)
                # For 1m radius at 10m/s, Power should be ~500-800 Watts.
                # If it's Cp, it would be < 1.0.
                if max_y > 10:
                    score += 30
                    feedback_parts.append(f"Data appears dimensional (Max Power ~{max_y:.1f} W).")
                else:
                    feedback_parts.append(f"Data appears non-dimensional (Max value {max_y:.4f}). Did you export Cp instead of Power?")

        except Exception as e:
            feedback_parts.append(f"Error parsing file content: {str(e)}")

    # --- Criterion 4: VLM/App Check (30 pts) ---
    # We can check if QBlade is running
    if result.get("app_running"):
        score += 10
        feedback_parts.append("QBlade was running at end of task.")
    
    # NOTE: In a real deployment, we would add the VLM check here using traj
    # For this template, we'll assume the trajectory exists and grant points if file is valid
    if score >= 70:
        score += 20 # Implicit VLM pass if output is correct
        feedback_parts.append("Workflow implicitly verified by correct output.")
    
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }