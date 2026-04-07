#!/usr/bin/env python3
"""
Verifier for science_payload_capacity_sweep task.

Scoring breakdown (100 points total):
  10 pts - All output files created (CSV, TXT, ORK).
  10 pts - CSV is correctly formatted with specified headers.
  20 pts - Physical trend validated (apogee and mach strictly decrease as mass increases).
  30 pts - Anti-gaming / Ground truth match: the 4.0kg CSV apogee matches the saved ORK simulation XML max altitude.
  15 pts - Final ORK file contains the "Science Payload" mass component sized to 4.0 kg.
  15 pts - Mathematical accuracy: text report correctly lists the computed average loss metric.

Pass threshold: 65 points AND header correctly formatted AND ground-truth match confirmed.
"""

import os
import json
import csv
import re
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
    except Exception as e:
        return None, str(e)


def verify_science_payload_capacity_sweep(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    csv_vm_path = metadata.get('csv_vm_path', '/home/ga/Documents/exports/payload_curve.csv')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/payload_summary.txt')
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/valetudo_payload_4kg.ork')

    score = 0
    feedback_parts = []
    
    # ---- Check 1: File Existence (10 points) ----
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env("/tmp/payload_sweep_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            res = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": "Failed to read export result JSON"}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)
            
    csv_exists = res.get('csv_exists', False)
    report_exists = res.get('report_exists', False)
    ork_exists = res.get('ork_exists', False)
    
    if csv_exists and report_exists and ork_exists:
        score += 10
        feedback_parts.append("All expected files exist [10/10 pts]")
    else:
        feedback_parts.append("Missing one or more expected output files [0/10 pts]")
        
    if not csv_exists:
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts) + " (CSV file missing)"
        }
        
    # ---- Check 2: CSV Formatting (10 points) ----
    tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    tmp_csv.close()
    csv_rows = []
    try:
        copy_from_env(csv_vm_path, tmp_csv.name)
        with open(tmp_csv.name, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            csv_rows = list(reader)
    except Exception as e:
        feedback_parts.append(f"Failed to read CSV: {e}")
    finally:
        if os.path.exists(tmp_csv.name):
            os.unlink(tmp_csv.name)
            
    header_correct = False
    if len(csv_rows) > 0:
        header = [c.strip().lower() for c in csv_rows[0]]
        if header == ['payload_mass_kg', 'apogee_m', 'max_mach']:
            header_correct = True

    # Ignore header for data processing if it exists
    data_rows = csv_rows[1:] if len(csv_rows) > 0 and any(c.isalpha() for c in csv_rows[0][0]) else csv_rows
    
    parsed_data = []
    for row in data_rows:
        if len(row) >= 3:
            try:
                m = float(row[0])
                a = float(row[1])
                v = float(row[2])
                parsed_data.append((m, a, v))
            except ValueError:
                pass
                
    if header_correct and len(parsed_data) >= 4:
        score += 10
        feedback_parts.append("CSV formatting correct with valid headers [10/10 pts]")
    elif len(parsed_data) >= 4:
        score += 5
        feedback_parts.append("CSV has sufficient data but headers incorrect [5/10 pts]")
    else:
        feedback_parts.append(f"CSV missing data (found {len(parsed_data)} valid numerical rows) [0/10 pts]")
        
    # ---- Check 3: Physical Trend Validated (20 points) ----
    trend_correct = False
    if len(parsed_data) >= 4:
        parsed_data.sort(key=lambda x: x[0])  # ensure sorted by mass
        apogees = [x[1] for x in parsed_data]
        machs = [x[2] for x in parsed_data]
        
        # Apogee and mach must be strictly decreasing as payload mass increases
        apogee_dec = all(apogees[i] > apogees[i+1] for i in range(len(apogees)-1))
        mach_dec = all(machs[i] >= machs[i+1] for i in range(len(machs)-1))
        
        if apogee_dec and mach_dec:
            trend_correct = True
            score += 20
            feedback_parts.append("Physical trend validated (apogee/mach decreasing with mass) [20/20 pts]")
        else:
            feedback_parts.append("Physical trend invalid (apogee/mach not decreasing properly) [0/20 pts]")
            
    # ---- Check 4 & 5: Final ORK State & Ground Truth Match (15 + 30 points) ----
    ork_apogee = None
    mass_component_found = False
    
    if ork_exists:
        tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
        tmp_ork.close()
        try:
            copy_from_env(ork_vm_path, tmp_ork.name)
            ork_root, parse_err = _parse_ork(tmp_ork.name)
            
            if ork_root is not None:
                # Identify if 4.0kg mass component was actually saved
                for mc in ork_root.iter('masscomponent'):
                    mass_txt = mc.findtext('mass', '0')
                    try:
                        m = float(mass_txt)
                        if abs(m - 4.0) < 0.1:  # check for roughly 4kg payload presence
                            mass_component_found = True
                            break
                    except ValueError:
                        pass
                        
                # Identify ground truth apogee inside the XML from the agent's run
                sims = ork_root.find('simulations')
                if sims is not None:
                    for sim in sims.findall('simulation'):
                        if sim.get('status') == 'uptodate':
                            fd = sim.find('flightdata')
                            if fd is not None:
                                try:
                                    ork_apogee = float(fd.get('maxaltitude', '0'))
                                    break
                                except ValueError:
                                    pass
        except Exception:
            pass
        finally:
            if os.path.exists(tmp_ork.name):
                os.unlink(tmp_ork.name)
                
    if mass_component_found:
        score += 15
        feedback_parts.append("Final ORK correctly contains 4.0kg mass component [15/15 pts]")
    else:
        feedback_parts.append("Final ORK missing 4.0kg mass component [0/15 pts]")
        
    gt_match = False
    if ork_apogee is not None and len(parsed_data) >= 4:
        # Match 4.0 kg row in CSV with internally tracked ORK apogee simulation data
        row_4kg = next((x for x in parsed_data if abs(x[0] - 4.0) < 0.1), None)
        if row_4kg is not None:
            csv_apogee_4kg = row_4kg[1]
            # Must be within 5% tolerance of actual XML readout
            if abs(csv_apogee_4kg - ork_apogee) / max(1, ork_apogee) < 0.05:
                gt_match = True
                score += 30
                feedback_parts.append("Ground-truth match verified (CSV non-hallucinated) [30/30 pts]")
            else:
                feedback_parts.append(f"Ground-truth mismatch: CSV {csv_apogee_4kg:.1f} vs XML {ork_apogee:.1f} [0/30 pts]")
        else:
            feedback_parts.append("4.0kg row missing from CSV for verification [0/30 pts]")
    else:
        feedback_parts.append("Could not verify ground truth match (ORK sim absent or CSV bad) [0/30 pts]")
        
    # ---- Check 6: Math Accuracy in Text Report (15 points) ----
    if report_exists and len(parsed_data) >= 4:
        row_1kg = next((x for x in parsed_data if abs(x[0] - 1.0) < 0.1), None)
        row_4kg = next((x for x in parsed_data if abs(x[0] - 4.0) < 0.1), None)
        
        if row_1kg and row_4kg:
            expected_loss = (row_1kg[1] - row_4kg[1]) / 3.0
            
            tmp_rep = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            tmp_rep.close()
            try:
                copy_from_env(report_vm_path, tmp_rep.name)
                with open(tmp_rep.name, 'r', encoding='utf-8') as f:
                    rep_text = f.read()
                    
                # Regex pulls all potential floating point combinations in text
                numbers = [float(x) for x in re.findall(r'-?\d+\.?\d*', rep_text)]
                
                # Verify if agent cited correct mathematics
                math_correct = any(abs(n - expected_loss) < max(0.5, expected_loss * 0.05) for n in numbers)
                
                if math_correct:
                    score += 15
                    feedback_parts.append(f"Math accuracy correct in report (~{expected_loss:.1f} m/kg) [15/15 pts]")
                else:
                    feedback_parts.append(f"Math accuracy incorrect or missing (expected ~{expected_loss:.1f} m/kg) [0/15 pts]")
            except Exception as e:
                feedback_parts.append(f"Failed to read report: {e}")
            finally:
                if os.path.exists(tmp_rep.name):
                    os.unlink(tmp_rep.name)
        else:
            feedback_parts.append("Could not calculate expected math baseline from CSV data [0/15 pts]")
    else:
        feedback_parts.append("Report missing or insufficient data available for math test [0/15 pts]")

    # Pass Requirements Criteria Filter
    passed = score >= 65 and header_correct and gt_match
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }