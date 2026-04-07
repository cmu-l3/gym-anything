#!/usr/bin/env python3
"""
Verifier for model_traffic_calming_zone task.
"""

import json
import tempfile
import os
import re
import math
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_tripinfo(filepath):
    """Parse tripinfo XML to compute average trip duration and total trips."""
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        durations = []
        for trip in root.findall('tripinfo'):
            duration = trip.get('duration')
            if duration:
                durations.append(float(duration))
        if not durations:
            return None, 0
        return sum(durations) / len(durations), len(durations)
    except Exception as e:
        logger.error(f"Error parsing {filepath}: {e}")
        return None, 0

def check_vss_validity(filepath):
    """Check if the VSS file defines a valid variable speed sign with speed <= 8.35 m/s."""
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        is_vss = False
        speed_correct = False
        
        for elem in root.iter():
            tag = elem.tag.lower()
            if 'vss' in tag or 'variablespeedsign' in tag:
                is_vss = True
            if 'speed' in elem.attrib:
                try:
                    if float(elem.attrib['speed']) <= 8.35:
                        speed_correct = True
                except ValueError:
                    pass
        return is_vss, speed_correct
    except Exception as e:
        logger.error(f"Error parsing VSS file {filepath}: {e}")
        return False, False

def verify_model_traffic_calming_zone(traj, env_info, task_info):
    """
    Verify the traffic calming task using multiple programmatic checks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Files to copy
    files_to_check = {
        "result": "/tmp/task_result.json",
        "vss": "/tmp/speed_zone.add.xml",
        "config": "/tmp/run_modified.sumocfg",
        "base_xml": "/tmp/baseline_tripinfo.xml",
        "mod_xml": "/tmp/modified_tripinfo.xml",
        "report": "/tmp/impact_report.txt"
    }
    
    local_files = {}
    
    try:
        for key, remote_path in files_to_check.items():
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            try:
                copy_from_env(remote_path, temp_file.name)
                # Check if it was actually copied (not empty or non-existent)
                if os.path.getsize(temp_file.name) > 0:
                    local_files[key] = temp_file.name
                else:
                    os.unlink(temp_file.name)
            except Exception as e:
                logger.warning(f"Could not copy {remote_path}: {e}")
                if os.path.exists(temp_file.name):
                    os.unlink(temp_file.name)
                    
        # 1. Check metadata and anti-gaming
        if "result" not in local_files:
            return {"passed": False, "score": 0, "feedback": "Task export metadata missing."}
            
        with open(local_files["result"], 'r') as f:
            result_meta = json.load(f)
            
        files_meta = result_meta.get("files", {})
        
        # 2. Verify VSS File (15 pts)
        if "vss" in local_files and files_meta.get("vss", {}).get("created_during_task", False):
            is_vss, speed_correct = check_vss_validity(local_files["vss"])
            if is_vss and speed_correct:
                score += 15
                feedback_parts.append("VSS file is valid and sets speed <= 30km/h")
            elif is_vss:
                score += 5
                feedback_parts.append("VSS file valid but speed > 30km/h")
            else:
                feedback_parts.append("VSS structure missing or invalid")
        else:
            feedback_parts.append("VSS file missing or pre-dates task")

        # 3. Verify Config File (10 pts)
        if "config" in local_files and files_meta.get("config", {}).get("created_during_task", False):
            try:
                cfg_tree = ET.parse(local_files["config"])
                cfg_root = cfg_tree.getroot()
                adds = cfg_root.find('input/additional-files')
                if adds is not None and ('speed_zone.add.xml' in adds.get('value', '')):
                    score += 10
                    feedback_parts.append("Modified config valid")
                else:
                    feedback_parts.append("Modified config does not load the new VSS file")
            except Exception:
                feedback_parts.append("Modified config is not valid XML")
        else:
            feedback_parts.append("Modified config missing or pre-dates task")

        # 4 & 5. Verify Tripinfos (30 pts)
        base_avg, base_count = None, 0
        mod_avg, mod_count = None, 0
        
        if "base_xml" in local_files and files_meta.get("baseline_tripinfo", {}).get("created_during_task", False):
            base_avg, base_count = parse_tripinfo(local_files["base_xml"])
            if base_avg is not None and base_count > 0:
                score += 15
                feedback_parts.append(f"Baseline parsed ({base_count} trips, avg {base_avg:.2f}s)")
        
        if "mod_xml" in local_files and files_meta.get("modified_tripinfo", {}).get("created_during_task", False):
            mod_avg, mod_count = parse_tripinfo(local_files["mod_xml"])
            if mod_avg is not None and mod_count > 0:
                score += 15
                feedback_parts.append(f"Modified parsed ({mod_count} trips, avg {mod_avg:.2f}s)")

        # 6. Verify differences indicating the VSS worked (10 pts)
        if base_avg is not None and mod_avg is not None:
            if not math.isclose(base_avg, mod_avg, rel_tol=1e-5):
                score += 10
                feedback_parts.append("Simulations show measurable difference")
            else:
                feedback_parts.append("Simulations identical (VSS had no effect)")

        # 7. Verify Impact Report Content (20 pts)
        if "report" in local_files and files_meta.get("report", {}).get("created_during_task", False):
            with open(local_files["report"], 'r') as f:
                report_content = f.read()
            
            score += 5
            feedback_parts.append("Impact report exists")
            
            # Extract all numbers from the report
            numbers = [float(x) for x in re.findall(r'[-+]?\d*\.\d+|\d+', report_content)]
            
            # Cross-check extracted numbers with our computed averages
            if base_avg is not None and mod_avg is not None:
                expected_pct = ((mod_avg - base_avg) / base_avg) * 100
                
                found_base = any(math.isclose(n, base_avg, rel_tol=0.05) for n in numbers)
                found_mod = any(math.isclose(n, mod_avg, rel_tol=0.05) for n in numbers)
                found_pct = any(math.isclose(n, expected_pct, rel_tol=0.1) or math.isclose(n, abs(expected_pct), rel_tol=0.1) for n in numbers)
                
                if found_base and found_mod:
                    score += 10
                    feedback_parts.append("Report contains accurate averages")
                if found_pct:
                    score += 5
                    feedback_parts.append("Report contains accurate % change")
        else:
            feedback_parts.append("Impact report missing")
            
    finally:
        # Cleanup
        for path in local_files.values():
            if os.path.exists(path):
                os.unlink(path)

    passed = score >= 60 and (base_avg is not None and mod_avg is not None)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }