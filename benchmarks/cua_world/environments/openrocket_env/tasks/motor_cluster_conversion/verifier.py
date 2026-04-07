#!/usr/bin/env python3
"""
Verifier for motor_cluster_conversion task.

Scoring Breakdown (100 points total):
  10 pts - Output ORK file exists, differs from original, and is modified after task start
  30 pts - Motor mount has a 3+ motor cluster configuration explicitly defined in XML
  20 pts - Motors are assigned to the new cluster (XML validation)
  20 pts - An 'uptodate' flight simulation exists for the clustered design
  15 pts - Conversion report exists, has reasonable length (>100 chars), and mentions "cluster/3/motor"
   5 pts - Report additionally mentions specific metrics (altitude, velocity, stability)

Pass threshold: 60 points
  Do-nothing max: 0 (file unchanged, no cluster, no report)
"""

import os
import json
import tempfile
import zipfile
import xml.etree.ElementTree as ET


def _parse_ork(local_path):
    """Parse .ork ZIP+XML and return (root_element, error_string)."""
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        root = ET.fromstring(xml_bytes.decode('utf-8'))
        return root, None
    except zipfile.BadZipFile:
        try:
            tree = ET.parse(local_path)
            return tree.getroot(), None
        except Exception as e:
            return None, f"Could not parse .ork as ZIP or XML: {e}"
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"


def verify_motor_cluster_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('target_ork_path', '/home/ga/Documents/rockets/cluster_conversion.ork')
    report_vm_path = metadata.get('target_report_path', '/home/ga/Documents/exports/cluster_report.txt')
    pass_threshold = metadata.get('pass_threshold', 60)

    score = 0
    feedback_parts = []
    
    # ---- Read Exported JSON Metadata ----
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    
    export_data = {}
    try:
        copy_from_env('/tmp/cluster_result.json', tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Could not read exported results: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # ---- Check 1: File Existence & Modification (10 points) ----
    ork_exists = export_data.get('ork_exists', False)
    if not ork_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file cluster_conversion.ork not found. No work detected."
        }
        
    ork_md5 = export_data.get('ork_md5', '')
    base_md5 = export_data.get('base_md5', 'unknown')
    ork_mtime = export_data.get('ork_mtime', 0)
    task_start = export_data.get('task_start', 0)

    # Anti-gaming: File must actually be modified and saved during task
    if ork_md5 == base_md5:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file cluster_conversion.ork is identical to the starting rocket. No modifications made."
        }
    
    if ork_mtime < task_start:
        feedback_parts.append("Warning: cluster_conversion.ork was not modified during the task window.")
    else:
        score += 10
        feedback_parts.append("Modified rocket file saved successfully [10/10 pts]")

    # ---- Copy .ork file from VM for Deep Inspection ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse .ork XML: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Could not retrieve .ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | Failed to verify rocket internal configuration"
        }

    # ---- Check 2: 3-Motor Cluster Configured (30 points) ----
    # Look for clusterconfiguration tags in inner tubes
    has_3_cluster = False
    cluster_texts = [el.text.strip().lower() for el in ork_root.iter('clusterconfiguration') if el.text]
    
    for c_text in cluster_texts:
        if '3' in c_text:
            has_3_cluster = True
            break
            
    if has_3_cluster:
        score += 30
        feedback_parts.append("3-motor cluster configuration verified in design [30/30 pts]")
    elif cluster_texts:
        feedback_parts.append(f"Found cluster configuration(s) ({', '.join(cluster_texts)}), but no 3-motor pattern found [0/30 pts]")
    else:
        feedback_parts.append("No cluster configuration found on motor mounts [0/30 pts]")

    # ---- Check 3: Motors Assigned (20 points) ----
    motors = list(ork_root.iter('motor'))
    if len(motors) > 0:
        score += 20
        feedback_parts.append(f"Motors assigned to flight configuration [20/20 pts]")
    else:
        feedback_parts.append("No motors assigned to any flight configuration [0/20 pts]")

    # ---- Check 4: Simulation Run (20 points) ----
    sims = ork_root.find('simulations')
    uptodate_sim = False
    
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_sim = True
                break
                
    if uptodate_sim:
        score += 20
        feedback_parts.append("Found up-to-date simulation verifying flight [20/20 pts]")
    else:
        feedback_parts.append("No up-to-date simulations found (run a simulation to verify stability) [0/20 pts]")

    # ---- Check 5: Conversion Report (20 points max) ----
    report_exists = export_data.get('report_exists', False)
    if report_exists:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env(report_vm_path, tmp_report.name)
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
            
            # Sub-check 5a: Basic report contents (15 points)
            if len(content) > 100:
                has_cluster_kws = ('cluster' in content) and ('3' in content or 'three' in content)
                has_motor_kws = ('motor' in content or 'engine' in content)
                
                if has_cluster_kws and has_motor_kws:
                    score += 15
                    feedback_parts.append("Report exists and discusses the cluster conversion [15/15 pts]")
                    
                    # Sub-check 5b: Metrics mentioned (5 points)
                    has_metrics = any(kw in content for kw in ['alt', 'apogee']) and \
                                  any(kw in content for kw in ['vel', 'speed']) and \
                                  any(kw in content for kw in ['stab', 'margin'])
                    if has_metrics:
                        score += 5
                        feedback_parts.append("Report contains relevant flight metrics [5/5 pts]")
                    else:
                        feedback_parts.append("Report is missing specific flight metrics (altitude, velocity, stability) [0/5 pts]")
                else:
                    score += 5
                    feedback_parts.append("Report exists but missing key vocabulary ('cluster', '3', 'motor') [5/15 pts]")
            else:
                feedback_parts.append("Report is too short (<100 characters) to be comprehensive [0/15 pts]")
                
        except Exception as e:
            feedback_parts.append(f"Could not read report file: {e}")
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback_parts.append("No conversion report found [0/20 pts]")

    # ---- Final Output ----
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }