#!/usr/bin/env python3
"""
Verifier for snr_multiwavelength_correlation task.

Occupation: Astrophysicist / High-Energy Astronomer
Context: Multi-wavelength observation of 3 supernova remnants (Tycho, Crab, Cas A).

Criteria (100 pts total, pass >= 70):
1. Tycho Optical (>=3 Ha, >=3 OIII)       - 10 pts
2. Crab Optical (>=3 Ha, >=3 OIII)        - 10 pts
3. Cas A Optical (>=3 Ha, >=3 OIII)       - 10 pts
4. Tycho Survey (dust + energy maps)      - 10 pts
5. Crab Survey (dust + energy maps)       - 10 pts
6. Cas A Survey (dust + energy maps)      - 10 pts
7. Survey Uniqueness (hash check)         - 15 pts (CRITICAL - ensures agent slewed between targets)
8. Directory Structure correctness        - 15 pts
9. Summary Report                         - 10 pts

Anti-gaming:
- Only files created after task_start are counted.
- Stale Crab files pre-seeded in setup will be ignored due to mtime constraint.
- MD5 hashes of `thermal_dust.png` are compared to ensure the telescope moved between captures.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_target_name(name):
    """Normalize directory names to match the 3 targets robustly."""
    upper = name.upper().replace('_', '').replace(' ', '')
    if 'TYCH' in upper:
        return 'Tycho'
    elif 'CRAB' in upper or 'M1' in upper:
        return 'Crab'
    elif 'CAS' in upper:
        return 'CasA'
    return 'Unknown'


def verify_snr_multiwavelength_correlation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = result.get('task_start', 0)
    files_info = result.get('files_info', [])

    # Filter out files created before the task or too small
    valid_files = [f for f in files_info if f.get('mtime', 0) > task_start and f.get('size', 0) > 1024]

    # Structure objects
    optical_counts = {'Tycho': {'Ha': 0, 'OIII': 0}, 'Crab': {'Ha': 0, 'OIII': 0}, 'CasA': {'Ha': 0, 'OIII': 0}}
    survey_files = {'Tycho': set(), 'Crab': set(), 'CasA': set()}
    thermal_dust_hashes = []
    
    strict_structure = True

    for f in valid_files:
        norm_target = normalize_target_name(f.get('target', ''))
        subdir = f.get('subdir', '').lower()
        name = f.get('name', '')
        
        if subdir not in ['optical', 'survey']:
            strict_structure = False

        if norm_target in optical_counts:
            # Check Optical FITS
            if name.lower().endswith('.fits') or name.lower().endswith('.fit'):
                if subdir != 'optical':
                    strict_structure = False
                
                # Use FITS header if available, otherwise guess from filename
                filt = f.get('filter', '').upper()
                if 'HA' in filt or 'HA' in name.upper():
                    optical_counts[norm_target]['Ha'] += 1
                elif 'OIII' in filt or 'OIII' in name.upper():
                    optical_counts[norm_target]['OIII'] += 1
            
            # Check Survey PNGs
            elif name.lower().endswith('.png'):
                if subdir != 'survey':
                    strict_structure = False
                    
                if 'thermal_dust' in name.lower():
                    survey_files[norm_target].add('dust')
                    h = f.get('md5')
                    if h:
                        thermal_dust_hashes.append(h)
                elif 'high_energy' in name.lower():
                    survey_files[norm_target].add('energy')

    # 1-3. Optical Scores (30 pts total)
    for tgt in ['Tycho', 'Crab', 'CasA']:
        ha = optical_counts[tgt]['Ha']
        oiii = optical_counts[tgt]['OIII']
        if ha >= 3 and oiii >= 3:
            score += 10
            feedback.append(f"{tgt} Optical: OK (Ha:{ha}, OIII:{oiii})")
        elif ha >= 1 or oiii >= 1:
            score += 5
            feedback.append(f"{tgt} Optical: Partial (Ha:{ha}, OIII:{oiii})")
        else:
            feedback.append(f"{tgt} Optical: Missing")

    # 4-6. Survey Scores (30 pts total)
    for tgt in ['Tycho', 'Crab', 'CasA']:
        sf = survey_files[tgt]
        if 'dust' in sf and 'energy' in sf:
            score += 10
            feedback.append(f"{tgt} Survey: OK (Dust & Energy maps present)")
        elif 'dust' in sf or 'energy' in sf:
            score += 5
            feedback.append(f"{tgt} Survey: Partial (Only 1 map present)")
        else:
            feedback.append(f"{tgt} Survey: Missing")

    # 7. Survey Uniqueness / Anti-Gaming (15 pts)
    unique_hashes = len(set(thermal_dust_hashes))
    total_hashes = len(thermal_dust_hashes)
    if total_hashes >= 3 and unique_hashes >= 3:
        score += 15
        feedback.append("Survey Uniqueness: Passed (Images from different telescope positions)")
    elif total_hashes > 0:
        feedback.append(f"Survey Uniqueness: Failed ({unique_hashes} unique hashes out of {total_hashes} images) - Telescope wasn't slewed between targets properly.")
    else:
        feedback.append("Survey Uniqueness: N/A (No thermal dust images generated)")

    # 8. Directory Structure Correctness (15 pts)
    # Give points if they correctly sorted files into <Target>/optical/ and <Target>/survey/
    # If valid_files is empty, give 0.
    if len(valid_files) > 0 and strict_structure:
        score += 15
        feedback.append("Directory Structure: Correct")
    elif len(valid_files) > 0:
        score += 5
        feedback.append("Directory Structure: Partially Correct (Some files miscategorized)")
    else:
        feedback.append("Directory Structure: Failed (No valid files)")

    # 9. Summary Report (10 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_b64', '')
    
    if report_exists and report_mtime > task_start:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').upper()
            mentions = 0
            if 'TYCHO' in report_text: mentions += 1
            if 'CRAB' in report_text or 'M1' in report_text: mentions += 1
            if 'CAS' in report_text: mentions += 1
            
            if mentions >= 2:
                score += 10
                feedback.append("Report: OK (Contains targets)")
            else:
                score += 5
                feedback.append("Report: Created but lacking target mentions")
        except:
            score += 5
            feedback.append("Report: Created but unreadable")
    else:
        feedback.append("Report: Missing or stale")

    # Final pass determination
    # Must get at least 70 points to pass, AND must have unique survey images
    key_criteria = (unique_hashes >= 3 and score >= 70)
    passed = key_criteria
    
    if score >= 70 and not passed:
        feedback.append("FAILED: Score was high enough, but Survey Uniqueness check failed.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }