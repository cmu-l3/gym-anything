#!/usr/bin/env python3
"""
Verifier for perimeter_furnace_degradation_analysis task.

Checks:
1. Simulation was run (new .SIM file created).
2. All 12 Perimeter systems have FURNACE-HIR = 1.389 ± 0.005.
3. All 3 Core systems DO NOT have FURNACE-HIR = 1.389 (should be original ~1.24/1.25).

Systems:
- Perimeter: G.N*, G.E*, G.S*, G.W*, M.N*, ..., T.W* (12 total)
- Core: G.C*, M.C*, T.C* (3 total)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_inp_systems(inp_content):
    """
    Parses eQUEST .inp content to extract SYSTEM names and their FURNACE-HIR values.
    Returns a dict: { 'SystemName': float(HIR_Value) }
    If FURNACE-HIR is missing for a system, it defaults to None.
    """
    systems = {}
    current_system = None
    
    # Regex to identify system start: "Name" = SYSTEM
    sys_start_re = re.compile(r'"([^"]+)"\s*=\s*SYSTEM')
    # Regex for FURNACE-HIR
    hir_re = re.compile(r'FURNACE-HIR\s*=\s*([0-9.]+)')
    # Regex for end of object (simple approximation for INP structure)
    end_re = re.compile(r'\.\.')

    for line in inp_content.splitlines():
        line = line.strip()
        
        # Check for new system
        m_sys = sys_start_re.search(line)
        if m_sys:
            current_system = m_sys.group(1)
            systems[current_system] = None # Initialize
            continue
            
        # If inside a system, look for parameters
        if current_system:
            m_hir = hir_re.search(line)
            if m_hir:
                try:
                    systems[current_system] = float(m_hir.group(1))
                except ValueError:
                    pass
            
            # Check for end of block (.. often denotes end of major object in DOE-2 BDL, 
            # though nested objects make this tricky. 
            # Ideally we just keep parsing until next SYSTEM or EOF, 
            # keeping the last found HIR for the current system.)
            
    return systems

def verify_perimeter_furnace_degradation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # File paths in container
    result_json_path = "C:\\Users\\Docker\\task_result.json"
    inp_file_path = "C:\\Users\\Docker\\Documents\\eQUEST 3-65 Projects\\4StoreyBuilding\\4StoreyBuilding.inp"

    # 1. Get JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_json_path, temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Get INP file
    temp_inp = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
    try:
        copy_from_env(inp_file_path, temp_inp.name)
        with open(temp_inp.name, 'r', encoding='latin-1') as f: # .inp often latin-1
            inp_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve project file: {e}"}
    finally:
        if os.path.exists(temp_inp.name):
            os.unlink(temp_inp.name)

    # Scoring Setup
    score = 0
    feedback = []
    
    # Criterion 1: Simulation Ran (10 pts)
    if result_data.get('sim_ran', False):
        score += 10
        feedback.append("Simulation ran successfully (+10).")
    else:
        feedback.append("Simulation did not run or .SIM file not updated.")

    # Parse Systems
    systems_data = parse_inp_systems(inp_content)
    
    # Patterns
    perimeter_pattern = re.compile(r'^[GMT]\.[NESW].*')
    core_pattern = re.compile(r'^[GMT]\.C.*')
    target_hir = 1.389
    tolerance = 0.005

    perimeter_correct = 0
    perimeter_total = 0
    core_preserved = 0
    core_total = 0

    for sys_name, hir in systems_data.items():
        # Check matching logic
        is_perimeter = bool(perimeter_pattern.match(sys_name))
        is_core = bool(core_pattern.match(sys_name))
        
        # Only care about the HVAC systems for floors G, M, T (ignoring basement if any)
        if not (is_perimeter or is_core):
            continue

        if is_perimeter:
            perimeter_total += 1
            if hir is not None and abs(hir - target_hir) <= tolerance:
                perimeter_correct += 1
            else:
                feedback.append(f"Perimeter system {sys_name} incorrect (HIR={hir}, expected {target_hir}).")
        
        if is_core:
            core_total += 1
            # Check preservation: Should NOT match target_hir
            # Default is usually ~1.25. If they global replaced, it will be 1.389
            if hir is None or abs(hir - target_hir) > tolerance:
                core_preserved += 1
            else:
                feedback.append(f"Core system {sys_name} was incorrectly modified to {hir}.")

    # Criterion 2: Perimeter Systems (72 pts total, 6 per system)
    # Expecting 12 perimeter systems (4 per floor * 3 floors)
    if perimeter_total == 0:
        feedback.append("No perimeter systems found to verify.")
    else:
        pts_per_sys = 6
        p_score = perimeter_correct * pts_per_sys
        score += p_score
        feedback.append(f"Perimeter systems corrected: {perimeter_correct}/{perimeter_total} (+{p_score}).")

    # Criterion 3: Core Systems Preserved (18 pts total, 6 per system)
    # Expecting 3 core systems
    if core_total == 0:
        feedback.append("No core systems found to verify.")
    else:
        pts_per_sys = 6
        c_score = core_preserved * pts_per_sys
        score += c_score
        feedback.append(f"Core systems preserved: {core_preserved}/{core_total} (+{c_score}).")

    # Final logic
    passed = (score >= 70) and result_data.get('sim_ran', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }