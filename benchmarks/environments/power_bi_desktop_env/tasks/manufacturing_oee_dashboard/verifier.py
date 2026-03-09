#!/usr/bin/env python3
"""
Verifier for manufacturing_oee_dashboard.

Scoring (100 pts):
- PBIX File Saved (10 pts)
- Measures Created (30 pts): Availability_Pct, Quality_Pct, Performance_Pct, OEE_Score found in DataModel.
- Visuals Created (30 pts): Gauge Chart (15), Matrix/PivotTable (15).
- Calculation Accuracy (30 pts): Checked against CSV export vs Ground Truth.
"""

import json
import logging
import os
import io
import csv
import tempfile

logger = logging.getLogger(__name__)

def verify_manufacturing_oee_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\tasks\\manufacturing_oee_dashboard\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence (10 pts)
    if result.get('pbix_exists', False):
        score += 10
        feedback.append("✅ PBIX file saved.")
    else:
        feedback.append("❌ PBIX file not found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # 2. Measures Check (30 pts)
    found_measures = result.get('measures_found', [])
    required_measures = ["Availability_Pct", "Quality_Pct", "Performance_Pct", "OEE_Score"]
    measures_score = 0
    missing_measures = []
    
    for m in required_measures:
        # Case insensitive check
        if any(m.lower() == fm.lower() for fm in found_measures):
            measures_score += 7.5
        else:
            missing_measures.append(m)
            
    score += measures_score
    if not missing_measures:
        feedback.append("✅ All DAX measures found in DataModel.")
    else:
        feedback.append(f"❌ Missing measures: {', '.join(missing_measures)}.")

    # 3. Visuals Check (30 pts)
    visuals = result.get('visual_types_found', [])
    
    if "gaugeChart" in visuals:
        score += 15
        feedback.append("✅ Gauge chart found.")
    else:
        feedback.append("❌ Gauge chart not found.")
        
    if "pivotTable" in visuals:
        score += 15
        feedback.append("✅ Matrix visual found.")
    else:
        feedback.append("❌ Matrix visual not found.")

    # 4. Calculation Accuracy (30 pts)
    # Compare exported CSV with Ground Truth
    csv_exists = result.get('csv_exists', False)
    ground_truth_str = result.get('ground_truth', '{}')
    
    if csv_exists and ground_truth_str:
        try:
            gt_data = json.loads(ground_truth_str)
            csv_content = result.get('csv_content', '')
            
            # Parse agent's CSV
            # Expecting columns: Machine_ID, measures...
            # We need to find the OEE_Score column
            f = io.StringIO(csv_content)
            reader = csv.DictReader(f)
            
            matches = 0
            checked = 0
            
            for row in reader:
                # Find the machine ID key
                machine_id = None
                for k, v in row.items():
                    if v in gt_data:
                        machine_id = v
                        break
                
                if machine_id and machine_id in gt_data:
                    checked += 1
                    # Find OEE value in row
                    agent_oee = None
                    # Try to find a column header that looks like OEE
                    for k, v in row.items():
                        if "OEE" in k and v:
                            try:
                                # Clean string (remove %)
                                val_str = v.replace('%', '').strip()
                                agent_oee = float(val_str)
                                # If percentage was 85%, float might be 85 or 0.85 depending on formatting
                                # GT is 0.85 format. If agent is > 1, divide by 100
                                if agent_oee > 1.0:
                                    agent_oee /= 100.0
                            except:
                                pass
                    
                    if agent_oee is not None:
                        gt_oee = gt_data[machine_id]['OEE_Score']
                        # Tolerance 1%
                        if abs(agent_oee - gt_oee) < 0.01:
                            matches += 1
            
            if checked > 0:
                if matches == checked:
                    score += 30
                    feedback.append(f"✅ OEE Calculations accurate for {matches}/{checked} machines.")
                elif matches > 0:
                    score += 15
                    feedback.append(f"⚠️ OEE Calculations partially correct ({matches}/{checked}).")
                else:
                    feedback.append("❌ OEE Calculations incorrect.")
            else:
                feedback.append("❌ Could not parse machine IDs from CSV.")
                
        except Exception as e:
            feedback.append(f"❌ Error verifying CSV data: {e}")
    else:
        feedback.append("❌ CSV summary export not found or empty.")

    # 5. Anti-gaming check (informational for score, hard fail if logic demands)
    if not result.get('file_created_after_start', True):
         feedback.append("⚠️ Warning: File timestamp is older than task start.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "\n".join(feedback)
    }