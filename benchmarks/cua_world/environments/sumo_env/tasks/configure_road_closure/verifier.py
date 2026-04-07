#!/usr/bin/env python3
"""
Verifier for configuring road closures and evaluating vehicle rerouting in SUMO.
Programmatically parses the modified configurations, outputs, and analytical reports 
to ensure the road closure logic was effectively established and computed correctly.
"""

import os
import json
import xml.etree.ElementTree as ET
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_road_closure(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function not available."}

    with tempfile.TemporaryDirectory() as tmpdir:
        # Define files required for complete verification
        files_to_copy = {
            "result": "/tmp/task_result.json",
            "target": "/tmp/closure_target_edge.txt",
            "start_time": "/tmp/task_start_time.txt",
            "rerouter": "/home/ga/SUMO_Scenarios/bologna_acosta/road_closure.add.xml",
            "sumocfg": "/home/ga/SUMO_Scenarios/bologna_acosta/closure_run.sumocfg",
            "closure_tripinfo": "/home/ga/SUMO_Scenarios/bologna_acosta/closure_tripinfo.xml",
            "baseline_tripinfo": "/home/ga/SUMO_Scenarios/bologna_acosta/baseline_tripinfo.xml",
            "report": "/home/ga/SUMO_Output/closure_report.txt"
        }
        
        local_files = {}
        for key, path in files_to_copy.items():
            local_path = os.path.join(tmpdir, key)
            try:
                copy_from_env(path, local_path)
                if os.path.exists(local_path):
                    local_files[key] = local_path
            except Exception as e:
                logger.warning(f"Could not copy {path}: {e}")
                
        if "result" not in local_files:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task export result json."}
            
        with open(local_files["result"], 'r') as f:
            result = json.load(f)
            
        target_edge = ""
        if "target" in local_files:
            with open(local_files["target"], 'r') as f:
                target_edge = f.read().strip()
                
        if not target_edge:
            return {"passed": False, "score": 0, "feedback": "Target edge mapping could not be resolved from environment."}
            
        task_start = result.get('task_start', 0)
        
        score = 0
        feedback_parts = []
        valid_xml = False
        sim_ran = False
        
        # 1. Rerouter configuration evaluation (up to 30 points)
        if "rerouter" in local_files:
            if result.get("rerouter_mtime", 0) > task_start:
                score += 5
                feedback_parts.append("Rerouter config created")
                try:
                    tree = ET.parse(local_files["rerouter"])
                    root = tree.getroot()
                    if root.tag == 'additional' and root.find('.//rerouter') is not None and root.find('.//interval') is not None and root.find('.//closingReroute') is not None:
                        score += 10
                        valid_xml = True
                        feedback_parts.append("Rerouter config structurally valid")
                        
                        found_in_edges = False
                        found_in_closing = False
                        for rerouter in root.findall('.//rerouter'):
                            if target_edge in rerouter.get('edges', '').split():
                                found_in_edges = True
                        for closing in root.findall('.//closingReroute'):
                            if closing.get('id', '') == target_edge:
                                found_in_closing = True
                                
                        if found_in_edges and found_in_closing:
                            score += 10
                            feedback_parts.append("Target edge successfully configured in reroute properties")
                        elif found_in_edges or found_in_closing:
                            score += 5
                            feedback_parts.append("Target edge partially configured (missing in edges or closing list)")
                            
                        # Confirm duration covers the simulation block
                        for interval in root.findall('.//interval'):
                            try:
                                begin = float(interval.get('begin', '999999'))
                                end = float(interval.get('end', '0'))
                                if begin <= 0 and end >= 3600:
                                    score += 5
                                    feedback_parts.append("Proper operational interval configured")
                                    break
                            except:
                                pass
                    else:
                        feedback_parts.append("Rerouter XML is missing key routing tags")
                except Exception as e:
                    feedback_parts.append(f"Invalid rerouter XML syntax: {e}")
            else:
                feedback_parts.append("Rerouter file predates task sequence (gaming detected)")
        else:
            feedback_parts.append("Rerouter file completely missing")
            
        # 2. Simulation Configuration mapping (up to 15 points)
        if "sumocfg" in local_files:
            if result.get("sumocfg_mtime", 0) > task_start:
                score += 5
                feedback_parts.append("Modified SUMO config detected")
                try:
                    tree = ET.parse(local_files["sumocfg"])
                    root = tree.getroot()
                    
                    has_rerouter = False
                    for inp in root.iter('input'):
                        af = inp.find('additional-files')
                        if af is not None and 'road_closure.add.xml' in af.get('value', ''):
                            has_rerouter = True
                    for af in root.iter('additional-files'):
                        if 'road_closure.add.xml' in af.get('value', ''):
                            has_rerouter = True
                            
                    if has_rerouter:
                        score += 5
                        feedback_parts.append("SUMO config properly references rerouter config")
                        
                    has_tripinfo = False
                    for out in root.iter('output'):
                        ti = out.find('tripinfo-output')
                        if ti is not None and ti.get('value', ''):
                            has_tripinfo = True
                    for ti in root.iter('tripinfo-output'):
                        if ti.get('value', ''):
                            has_tripinfo = True
                            
                    if has_tripinfo:
                        score += 5
                        feedback_parts.append("Output recording initialized (tripinfo-output)")
                except:
                    feedback_parts.append("Malformed simulation config XML")
        else:
            feedback_parts.append("Modified simulation config completely missing")
            
        # 3. Post-execution outputs and logic confirmation (up to 25 points)
        if "closure_tripinfo" in local_files:
            if result.get("tripinfo_mtime", 0) > task_start:
                try:
                    tree = ET.parse(local_files["closure_tripinfo"])
                    trips = tree.findall('.//tripinfo')
                    if len(trips) >= 10:
                        score += 10
                        sim_ran = True
                        feedback_parts.append(f"Headless simulation executed dynamically ({len(trips)} logical trips)")
                        
                        closure_violations = 0
                        for trip in trips:
                            route = trip.find('route')
                            if route is not None:
                                if target_edge in route.get('edges', '').split():
                                    closure_violations += 1
                        if closure_violations == 0:
                            score += 15
                            feedback_parts.append("Closure simulation confirmed: Target edge strictly bypassed by all actors")
                        else:
                            feedback_parts.append(f"Closure failed: {closure_violations} vehicles still pathing through target edge")
                except:
                    feedback_parts.append("Failed to load/parse output trip records")
        else:
            feedback_parts.append("Simulation outputs not materialized (simulation was likely not run)")
                    
        # 4. Report verification & cross-validation (up to 30 points)
        report_complete = False
        if "report" in local_files:
            if result.get("report_mtime", 0) > task_start:
                score += 5
                feedback_parts.append("Statistical closure report compiled")
                
                req_fields = ["closed_edge", "baseline_trips", "closure_trips", "baseline_avg_duration", "closure_avg_duration", "duration_change_seconds", "duration_change_percent"]
                report_data = {}
                try:
                    with open(local_files["report"], 'r') as f:
                        for line in f:
                            m = re.match(r'^(\w+):\s*(.+)', line.strip())
                            if m:
                                report_data[m.group(1).strip()] = m.group(2).strip()
                except:
                    pass
                    
                fields_found = sum(1 for f in req_fields if f in report_data)
                if fields_found == 7:
                    score += 10
                    report_complete = True
                    feedback_parts.append("Closure report features all expected attributes")
                elif fields_found > 0:
                    partial = (fields_found * 10) // 7
                    score += partial
                    feedback_parts.append(f"Closure report contains {fields_found}/7 expected attributes")
                    
                # Content cross-validation mathematically confirms no fabrications
                if report_complete and sim_ran and "baseline_tripinfo" in local_files:
                    try:
                        def parse_ti(path):
                            t = ET.parse(path)
                            trps = t.findall('.//tripinfo')
                            cnt = len(trps)
                            tdur = sum(float(tr.get('duration', 0)) for tr in trps)
                            return cnt, (tdur/cnt if cnt>0 else 0)
                            
                        bl_cnt, bl_avg = parse_ti(local_files["baseline_tripinfo"])
                        cl_cnt, cl_avg = parse_ti(local_files["closure_tripinfo"])
                        
                        checks = 0
                        if report_data.get("closed_edge", "") == target_edge: checks += 1
                        
                        try:
                            r_bl_trips = int(report_data.get("baseline_trips", "0"))
                            if abs(r_bl_trips - bl_cnt) <= max(1, bl_cnt * 0.01): checks += 1
                        except ValueError:
                            pass
                        
                        try:
                            r_cl_trips = int(report_data.get("closure_trips", "0"))
                            if abs(r_cl_trips - cl_cnt) <= max(1, cl_cnt * 0.01): checks += 1
                        except ValueError:
                            pass
                        
                        try:
                            r_bl_avg = float(report_data.get("baseline_avg_duration", "0"))
                            if bl_avg > 0 and abs(r_bl_avg - bl_avg)/bl_avg <= 0.05: checks += 1
                            elif bl_avg == 0 and r_bl_avg == 0: checks += 1
                        except ValueError:
                            pass
                        
                        try:
                            r_cl_avg = float(report_data.get("closure_avg_duration", "0"))
                            if cl_avg > 0 and abs(r_cl_avg - cl_avg)/cl_avg <= 0.05: checks += 1
                            elif cl_avg == 0 and r_cl_avg == 0: checks += 1
                        except ValueError:
                            pass
                        
                        pts = (checks * 15) // 5
                        score += pts
                        feedback_parts.append(f"Quantitative cross-validation passed {checks}/5 mathematical checks")
                    except Exception as e:
                        logger.warning(f"Error during math validation: {e}")
                        
        # Global pass requires 60 overall, structurally valid rerouting, and active headless execution.
        passed = score >= 60 and valid_xml and sim_ran
        return {
            "passed": passed, 
            "score": min(score, 100), 
            "feedback": " | ".join(feedback_parts)
        }