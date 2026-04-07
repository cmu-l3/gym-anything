#!/usr/bin/env python3
"""
Verifier for evaluate_av_idm_impact task.

Evaluates the agent's ability to:
1. Generate baseline and AV simulation results using SUMO command line.
2. Properly copy and modify XML scenario configurations (vType carFollowModel).
3. Extract and compute mean travel times from tripinfos.xml.
4. Correctly output the comparison text file.
"""

import json
import os
import tempfile
import tarfile
import re
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)


def compute_mean_duration(xml_path):
    """Parse tripinfos.xml and compute mean trip duration."""
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        durations = []
        for trip in root.findall('tripinfo'):
            dur_str = trip.get('duration')
            if dur_str:
                durations.append(float(dur_str))
        if durations:
            return sum(durations) / len(durations)
        return None
    except Exception as e:
        logger.error(f"Failed to parse XML durations from {xml_path}: {e}")
        return None


def verify_evaluate_av_idm_impact(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env unavailable."}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the main results JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load task_result.json: {e}"}
    finally:
        os.unlink(temp_json.name)
        
    task_start = result_meta.get('task_start', 0)

    # 2. Check if baseline XML was created properly
    base_exists = result_meta.get('baseline_xml_exists', False)
    base_mtime = result_meta.get('baseline_xml_mtime', 0)
    
    base_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    base_duration = None
    if base_exists and base_mtime >= task_start:
        try:
            copy_from_env("/tmp/tripinfos_baseline.xml", base_tmp.name)
            base_duration = compute_mean_duration(base_tmp.name)
            if base_duration is not None:
                score += 15
                feedback_parts.append("Baseline simulation completed correctly")
            else:
                feedback_parts.append("Baseline XML lacks tripinfo data")
        except Exception:
            feedback_parts.append("Baseline XML invalid or not found")
    else:
        feedback_parts.append("Baseline XML not created during task")
    os.unlink(base_tmp.name)

    # 3. Check AV XML
    av_exists = result_meta.get('av_xml_exists', False)
    av_mtime = result_meta.get('av_xml_mtime', 0)
    
    av_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    av_duration = None
    if av_exists and av_mtime >= task_start:
        try:
            copy_from_env("/tmp/tripinfos_av.xml", av_tmp.name)
            av_duration = compute_mean_duration(av_tmp.name)
            if av_duration is not None:
                score += 15
                feedback_parts.append("AV simulation completed correctly")
            else:
                feedback_parts.append("AV XML lacks tripinfo data")
        except Exception:
            feedback_parts.append("AV XML invalid or not found")
    else:
        feedback_parts.append("AV XML not created during task")
    os.unlink(av_tmp.name)

    # 4. Verify IDM Modifications inside the scenario configuration
    # Extract the tarred scenario folder
    scenario_tar = tempfile.NamedTemporaryFile(delete=False, suffix='.tar.gz')
    extract_dir = tempfile.mkdtemp()
    idm_modified_correctly = False
    av_config_found = False
    
    try:
        copy_from_env("/tmp/bologna_acosta_scenario.tar.gz", scenario_tar.name)
        with tarfile.open(scenario_tar.name, "r:gz") as tar:
            tar.extractall(path=extract_dir)
            
        bologna_dir = os.path.join(extract_dir, "bologna_acosta")
        av_sumocfg_path = os.path.join(bologna_dir, "run_av.sumocfg")
        
        if os.path.exists(av_sumocfg_path):
            av_config_found = True
            score += 15
            feedback_parts.append("run_av.sumocfg created")
            
            # Parse run_av.sumocfg to find the vType file
            cfg_tree = ET.parse(av_sumocfg_path)
            files_to_check = []
            for tag in ['additional-files', 'route-files']:
                for el in cfg_tree.findall(f'.//input/{tag}'):
                    val = el.get('value')
                    if val:
                        files_to_check.extend([f.strip() for f in val.split(',')])
            
            for fname in files_to_check:
                fpath = os.path.join(bologna_dir, fname)
                if os.path.exists(fpath):
                    v_tree = ET.parse(fpath)
                    for vtype in v_tree.findall('.//vType'):
                        # Check if passenger class
                        if vtype.get('vClass') == 'passenger' or vtype.get('id', '').lower() in ['passenger', 'car']:
                            if vtype.get('carFollowModel') == 'IDM' and str(vtype.get('tau', '')) == '0.8':
                                idm_modified_correctly = True
                                break
                    if idm_modified_correctly:
                        break
        else:
            feedback_parts.append("run_av.sumocfg NOT found")
            
        if idm_modified_correctly:
            score += 20
            feedback_parts.append("IDM & tau=0.8 applied to passenger vType correctly")
        else:
            feedback_parts.append("Passenger vType not correctly modified to IDM with tau=0.8")

    except Exception as e:
        logger.error(f"Error checking scenario files: {e}")
        feedback_parts.append(f"Scenario files inspection failed: {str(e)[:50]}")
    finally:
        os.unlink(scenario_tar.name)
        import shutil
        shutil.rmtree(extract_dir, ignore_errors=True)

    # 5. Verify the text report
    comp_exists = result_meta.get('comparison_txt_exists', False)
    comp_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    if comp_exists:
        try:
            copy_from_env("/tmp/av_comparison.txt", comp_tmp.name)
            with open(comp_tmp.name, 'r') as f:
                content = f.read()
            
            # Check for the existence of the file format
            score += 5
            
            b_match = re.search(r"Baseline Avg Duration:\s*([\d\.]+)", content)
            a_match = re.search(r"AV Avg Duration:\s*([\d\.]+)", content)
            d_match = re.search(r"Difference.*?:\s*([\-\d\.]+)", content)
            
            if b_match and a_match and d_match and base_duration is not None and av_duration is not None:
                reported_base = float(b_match.group(1))
                reported_av = float(a_match.group(1))
                reported_diff = float(d_match.group(1))
                
                # Check within tolerance of actual calculated values
                base_ok = abs(reported_base - base_duration) <= 0.05
                av_ok = abs(reported_av - av_duration) <= 0.05
                diff_expected = base_duration - av_duration
                diff_ok = abs(reported_diff - diff_expected) <= 0.05
                
                if base_ok and av_ok and diff_ok:
                    score += 30
                    feedback_parts.append("Report metrics calculated accurately")
                else:
                    feedback_parts.append("Report metrics calculation inaccurate")
            else:
                feedback_parts.append("Report missing required lines or parsing failed")
        except Exception as e:
            feedback_parts.append("Failed to process comparison text file")
    else:
        feedback_parts.append("av_comparison.txt NOT found")
    os.unlink(comp_tmp.name)

    passed = score >= 70 and base_exists and av_exists and idm_modified_correctly
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }