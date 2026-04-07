#!/usr/bin/env python3
"""
Verifier for simulate_cordon_pricing_zone task.

VERIFICATION STRATEGY:
1. Parse base_edgedata.xml to verify execution and identify the true top 5 busiest standard edges.
2. Check pricing_weights.xml to see if the agent targeted the correct 5 edges.
3. Parse priced_routes.rou.xml for duarouter signature and valid routes.
4. Parse priced_edgedata.xml to verify simulation ran and to get after volumes.
5. Check pricing_report.txt for correct formatting and correct before/after values.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_simulate_cordon_pricing_zone(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch main export JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Dictionary to hold local paths of fetched files
    local_files = {}
    files_to_fetch = [
        "base_edgedata.xml",
        "pricing_weights.xml",
        "priced_routes.rou.xml",
        "priced_edgedata.xml",
        "pricing_report.txt"
    ]
    
    for filename in files_to_fetch:
        safe_name = filename.replace('.', '_')
        if result.get(f"{safe_name}_exists") and result.get(f"{safe_name}_size", 0) > 0:
            tf = tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(filename)[1])
            try:
                copy_from_env(f"/tmp/{filename}", tf.name)
                local_files[filename] = tf.name
            except Exception as e:
                logger.error(f"Failed to copy {filename}: {e}")
                if os.path.exists(tf.name):
                    os.unlink(tf.name)

    # Criteria tracking variables
    true_top_5 = []
    agent_targeted = []
    base_volumes = {}
    priced_volumes = {}
    
    # --- Criterion 1: Baseline Execution (15 points) ---
    if "base_edgedata.xml" in local_files:
        try:
            tree = ET.parse(local_files["base_edgedata.xml"])
            root = tree.getroot()
            
            # Aggregate entered counts for standard edges across the whole simulation
            for interval in root.findall('interval'):
                for edge in interval.findall('edge'):
                    eid = edge.get('id')
                    entered = float(edge.get('entered', 0))
                    if eid and ':' not in eid:  # Ignore internal edges
                        base_volumes[eid] = base_volumes.get(eid, 0) + entered
                        
            if len(base_volumes) > 0:
                score += 15
                feedback_parts.append("Base edgedata parsed successfully")
                
                # Identify true top 5
                sorted_edges = sorted(base_volumes.items(), key=lambda x: x[1], reverse=True)
                true_top_5 = [e[0] for e in sorted_edges[:5]]
            else:
                feedback_parts.append("Base edgedata contains no valid standard edge counts")
        except Exception as e:
            feedback_parts.append(f"Base edgedata XML invalid: {e}")
    else:
        feedback_parts.append("Base edgedata file missing")

    # --- Criterion 2: Target Identification & Weight Config (15 + 10 points) ---
    if "pricing_weights.xml" in local_files:
        try:
            tree = ET.parse(local_files["pricing_weights.xml"])
            root = tree.getroot()
            
            valid_weights = 0
            for edge in root.findall('edge'):
                eid = edge.get('id')
                tt = edge.get('traveltime', edge.get('value', '0'))
                if eid:
                    agent_targeted.append(eid)
                    try:
                        if float(tt) >= 1000.0:
                            valid_weights += 1
                    except ValueError:
                        pass
            
            # Check target matching
            if set(agent_targeted) == set(true_top_5) and len(true_top_5) == 5:
                score += 15
                feedback_parts.append("Correct 5 edges targeted")
            elif len(agent_targeted) > 0:
                matched = len(set(agent_targeted).intersection(set(true_top_5)))
                score += (matched * 3) # Partial credit
                feedback_parts.append(f"{matched}/5 correct edges targeted")
            
            if valid_weights > 0:
                score += 10
                feedback_parts.append("Valid traveltime weights applied")
                
        except Exception as e:
            feedback_parts.append(f"Pricing weights XML invalid: {e}")
    else:
        feedback_parts.append("Pricing weights file missing")

    # --- Criterion 3: Route Reassignment (20 points) ---
    if "priced_routes.rou.xml" in local_files:
        try:
            tree = ET.parse(local_files["priced_routes.rou.xml"])
            root = tree.getroot()
            vehicles = root.findall('vehicle')
            if len(vehicles) > 100:  # The Acosta scenario has many vehicles
                score += 20
                feedback_parts.append(f"Priced routes generated ({len(vehicles)} vehicles)")
            else:
                score += 10
                feedback_parts.append("Priced routes generated but vehicle count is low")
        except Exception as e:
            feedback_parts.append(f"Priced routes XML invalid: {e}")
    else:
        feedback_parts.append("Priced routes file missing")

    # --- Criterion 4: Alternative Simulation (20 points) ---
    if "priced_edgedata.xml" in local_files:
        try:
            tree = ET.parse(local_files["priced_edgedata.xml"])
            root = tree.getroot()
            
            for interval in root.findall('interval'):
                for edge in interval.findall('edge'):
                    eid = edge.get('id')
                    entered = float(edge.get('entered', 0))
                    if eid and ':' not in eid:
                        priced_volumes[eid] = priced_volumes.get(eid, 0) + entered
                        
            if len(priced_volumes) > 0:
                score += 20
                feedback_parts.append("Alternative simulation completed")
        except Exception as e:
            feedback_parts.append(f"Priced edgedata XML invalid: {e}")
    else:
        feedback_parts.append("Priced edgedata file missing")

    # --- Criterion 5: Report Accuracy (20 points) ---
    report_passed = False
    if "pricing_report.txt" in local_files:
        try:
            with open(local_files["pricing_report.txt"], 'r') as f:
                lines = [l.strip() for l in f.readlines() if l.strip()]
            
            if len(lines) == 6:
                header = lines[0].lower().replace(' ', '')
                if header == "edgeid,beforevolume,aftervolume":
                    report_content_score = 0
                    
                    # Validate the 5 data lines
                    for line in lines[1:]:
                        parts = [p.strip() for p in line.split(',')]
                        if len(parts) == 3:
                            eid, before, after = parts
                            # Verify accuracy if we have the truth data
                            if eid in base_volumes and eid in priced_volumes:
                                expected_before = base_volumes[eid]
                                expected_after = priced_volumes[eid]
                                
                                # Allow a small margin of error for reporting formats (floats vs ints)
                                try:
                                    if abs(float(before) - expected_before) <= 5 and abs(float(after) - expected_after) <= 5:
                                        report_content_score += 4 # 4 points per correct line * 5 = 20
                                except ValueError:
                                    pass
                                    
                    score += report_content_score
                    if report_content_score == 20:
                        report_passed = True
                        feedback_parts.append("Report accurately reflects volume reductions")
                    else:
                        feedback_parts.append(f"Report formatting correct, but data accuracy partial ({report_content_score}/20)")
                else:
                    feedback_parts.append("Report header format incorrect")
            else:
                feedback_parts.append(f"Report has {len(lines)} lines, expected 6")
        except Exception as e:
            feedback_parts.append(f"Error reading report: {e}")
    else:
        feedback_parts.append("Pricing report missing")

    # Clean up local temp files
    for filepath in local_files.values():
        if os.path.exists(filepath):
            os.unlink(filepath)

    key_criteria_met = ("priced_routes.rou.xml" in local_files) and len(agent_targeted) > 0
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }