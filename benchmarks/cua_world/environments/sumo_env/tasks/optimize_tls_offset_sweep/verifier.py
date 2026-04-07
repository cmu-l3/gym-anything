#!/usr/bin/env python3
"""
Verifier for optimize_tls_offset_sweep task.

Verifies that:
1. The Python automation script was written.
2. The CSV file was generated with the correct structure and variance.
3. The optimal XML configuration was exported with the correct offset.
4. Trajectory frames show the agent working on the script.
"""

import os
import json
import csv
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_tls_offset_sweep(traj, env_info, task_info):
    """Verify the offset optimization pipeline."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}

    metadata = task_info.get('metadata', {})
    script_path = metadata.get('script_path', '/home/ga/SUMO_Output/optimize_offset.py')
    csv_path = metadata.get('csv_path', '/home/ga/SUMO_Output/offset_results.csv')
    xml_path = metadata.get('xml_path', '/home/ga/SUMO_Output/best_tls.add.xml')

    score = 0
    feedback_parts = []
    
    # 1. Read the export summary JSON
    summary_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", summary_file.name)
        with open(summary_file.name, 'r') as f:
            export_summary = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export summary: {e}"}
    finally:
        if os.path.exists(summary_file.name):
            os.unlink(summary_file.name)

    # 2. Verify Python script exists and has content (15 points)
    script_stat = export_summary.get('script_file', {})
    if script_stat.get('exists') and script_stat.get('size', 0) > 50:
        if script_stat.get('created_during_task'):
            score += 15
            feedback_parts.append("Script created during task")
        else:
            score += 5
            feedback_parts.append("Script exists but not created during task")
    else:
        feedback_parts.append("Automation script missing or empty")

    # 3. Download and parse the CSV file
    csv_stat = export_summary.get('csv_file', {})
    csv_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    csv_parsed_successfully = False
    best_offset_from_csv = None
    
    if csv_stat.get('exists') and csv_stat.get('size', 0) > 0:
        try:
            copy_from_env(csv_path, csv_temp.name)
            
            with open(csv_temp.name, 'r', newline='') as f:
                reader = csv.reader(f)
                rows = list(reader)
                
            if len(rows) > 0:
                headers = [h.strip().lower() for h in rows[0]]
                if 'offset' in headers and 'total_waiting_time' in headers:
                    score += 10
                    feedback_parts.append("CSV headers correct")
                    
                    data_rows = rows[1:]
                    if len(data_rows) >= 13:
                        score += 10
                        feedback_parts.append("CSV row count correct (>=13)")
                        
                        # Validate the data and check variance
                        offsets_found = []
                        waiting_times = []
                        
                        offset_idx = headers.index('offset')
                        wait_idx = headers.index('total_waiting_time')
                        
                        for r in data_rows:
                            if len(r) > max(offset_idx, wait_idx):
                                try:
                                    off_val = int(float(r[offset_idx]))
                                    wait_val = float(r[wait_idx])
                                    offsets_found.append(off_val)
                                    waiting_times.append(wait_val)
                                except ValueError:
                                    continue
                        
                        if len(waiting_times) >= 13:
                            csv_parsed_successfully = True
                            
                            # Check variance (anti-gaming: are all waiting times identical?)
                            if len(set(waiting_times)) > 1:
                                score += 20
                                feedback_parts.append("Simulation variance verified")
                                
                                # Find optimal offset
                                min_wait = min(waiting_times)
                                min_idx = waiting_times.index(min_wait)
                                best_offset_from_csv = offsets_found[min_idx]
                            else:
                                feedback_parts.append("Simulation output spoofed or failed (zero variance in waiting times)")
                        else:
                            feedback_parts.append("Could not parse numeric data in CSV")
                else:
                    feedback_parts.append("CSV missing required headers")
            else:
                feedback_parts.append("CSV is empty")
        except Exception as e:
            feedback_parts.append(f"Failed to parse CSV: {e}")
        finally:
            if os.path.exists(csv_temp.name):
                os.unlink(csv_temp.name)
    else:
        feedback_parts.append("CSV file missing")

    # 4. Download and parse the optimal XML file (25 points)
    xml_stat = export_summary.get('xml_file', {})
    xml_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    
    if xml_stat.get('exists') and xml_stat.get('size', 0) > 0 and csv_parsed_successfully:
        try:
            copy_from_env(xml_path, xml_temp.name)
            tree = ET.parse(xml_temp.name)
            root = tree.getroot()
            
            first_tl = root.find('.//tlLogic')
            if first_tl is not None:
                xml_offset_str = first_tl.get('offset')
                if xml_offset_str is not None:
                    try:
                        xml_offset = int(float(xml_offset_str))
                        if best_offset_from_csv is not None and xml_offset == best_offset_from_csv:
                            score += 25
                            feedback_parts.append(f"Optimal XML matches best CSV offset ({xml_offset})")
                        else:
                            feedback_parts.append(f"XML offset ({xml_offset}) does not match CSV optimum ({best_offset_from_csv})")
                    except ValueError:
                        feedback_parts.append("Invalid offset attribute in XML")
                else:
                    feedback_parts.append("First tlLogic missing offset attribute")
            else:
                feedback_parts.append("No tlLogic found in exported XML")
                
        except ET.ParseError:
            feedback_parts.append("Exported XML is malformed")
        except Exception as e:
            feedback_parts.append(f"Failed to parse XML: {e}")
        finally:
            if os.path.exists(xml_temp.name):
                os.unlink(xml_temp.name)
    elif not xml_stat.get('exists'):
        feedback_parts.append("Optimal XML file missing")

    # 5. VLM Trajectory Verification (20 points)
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        
        prompt = (
            "Review these screenshots from a user's desktop session. "
            "Did the user write a Python script in an editor/IDE and execute it in a terminal? "
            "Respond with a JSON object: {\"script_written\": true/false, \"terminal_used\": true/false}"
        )
        
        vlm_resp = query_vlm(images=frames, prompt=prompt)
        if vlm_resp and vlm_resp.get("parsed"):
            parsed = vlm_resp["parsed"]
            if parsed.get("script_written") and parsed.get("terminal_used"):
                score += 20
                feedback_parts.append("VLM verified script creation and execution")
            else:
                score += 5
                feedback_parts.append("VLM could not definitively verify script execution")
        else:
            # Fallback points if VLM fails but structural checks passed
            score += 10
            feedback_parts.append("VLM parsing failed, partial credit given")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        # Give fallback points to not penalize agent for framework issues
        score += 10
        feedback_parts.append("VLM check skipped")

    # Final scoring
    # Requirements to pass: MUST have >0 variance in CSV and the correct optimal XML exported
    key_criteria_met = csv_parsed_successfully and (best_offset_from_csv is not None) and ('Optimal XML matches' in " ".join(feedback_parts))
    
    passed = score >= 70 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }