#!/usr/bin/env python3
"""
Verifier for parametric_window_retrofit_analysis task.

Goal: Verify that a Parametric Run was configured to improve window properties
without permanently modifying the baseline geometry.

Scoring Criteria:
1. Parametric Run Created (30 pts): A valid RUN command exists in INP file.
2. Component Mod targets Glass (20 pts): COMPONENT-MODIFICATION targets GLASS-TYPE.
3. Correct Parameters (30 pts): SC=0.35 and U=0.28 set in the modification.
4. Baseline Preservation (10 pts): Original Glass Types still have default/high values.
5. Simulation Run (10 pts): .SIM file updated.

Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_parametric_window_retrofit_analysis(traj, env_info, task_info):
    """
    Verify the eQUEST parametric run task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: The PS1 script saves to C:\workspace\tasks\..., but copy_from_env 
        # maps to the container path. In equest_env, mounts are:
        # examples/equest_env/tasks -> /workspace/tasks
        # So we copy from the linux path inside the container.
        copy_from_env("/workspace/tasks/parametric_window_retrofit_analysis/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result file. Ensure the script ran completely. Error: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    metadata = task_info.get('metadata', {})
    target_sc = metadata.get('target_shgc', 0.35)
    target_u = metadata.get('target_conductance', 0.28)
    tolerance = metadata.get('tolerance', 0.02)

    # 1. Check for Simulation (10 pts)
    if result.get('sim_file_is_new', False):
        score += 10
        feedback_parts.append("Simulation ran successfully (+10)")
    elif result.get('sim_file_exists', False):
        feedback_parts.append("Simulation output exists but is old (did not run during task)")
    else:
        feedback_parts.append("Simulation output NOT found")

    # 2. Check for Parametric Run Definition (30 pts)
    if result.get('run_command_found', False):
        score += 30
        feedback_parts.append("Parametric Run definition found (+30)")
    else:
        feedback_parts.append("No Parametric Run definition found")

    # 3. Check Modifications (20 pts targeting, 30 pts values)
    mods = result.get('modifications', [])
    valid_mod_found = False
    values_correct = False
    
    for mod in mods:
        # Check targeting
        if mod.get('targets_glass_type', False):
            # Check target scope (wildcard * or specific GT-1)
            target_name = mod.get('target_name', '')
            if target_name == '*' or 'GT' in target_name:
                valid_mod_found = True
                
                # Check values
                try:
                    sc = float(mod.get('shading_coef', -1))
                    u = float(mod.get('glass_conductance', -1))
                    
                    sc_ok = abs(sc - target_sc) <= tolerance
                    u_ok = abs(u - target_u) <= tolerance
                    
                    if sc_ok and u_ok:
                        values_correct = True
                        break # Found a perfect mod
                except (ValueError, TypeError):
                    continue

    if valid_mod_found:
        score += 20
        feedback_parts.append("Valid Component Modification for Glass Type found (+20)")
    else:
        feedback_parts.append("No valid modification targeting Glass Types found")

    if values_correct:
        score += 30
        feedback_parts.append(f"Modification parameters correct (SC={target_sc}, U={target_u}) (+30)")
    elif valid_mod_found:
        feedback_parts.append("Modification found but parameters incorrect")

    # 4. Check Baseline Preservation (10 pts)
    # We verify that the BASELINE glass types in the .inp file were NOT modified
    # Default SC is usually ~0.8-0.9, U is ~0.5-1.0 for standard glass
    baseline_preserved = True
    current_glass = result.get('current_baseline_glass_types', [])
    
    for glass in current_glass:
        try:
            # If values are "Default", that's good (means they aren't explicitly overridden in the main block)
            # If they are numbers, they should NOT match the retrofit target
            sc_val = glass.get('shading_coef', 'Default')
            u_val = glass.get('glass_conductance', 'Default')
            
            if sc_val != 'Default':
                sc_float = float(sc_val)
                if abs(sc_float - target_sc) < tolerance:
                    baseline_preserved = False
                    
            if u_val != 'Default':
                u_float = float(u_val)
                if abs(u_float - target_u) < tolerance:
                    baseline_preserved = False
        except:
            pass
            
    if baseline_preserved and len(current_glass) > 0:
        score += 10
        feedback_parts.append("Baseline glass types preserved (+10)")
    elif len(current_glass) == 0:
        feedback_parts.append("No glass types found in model (error)")
    else:
        # If baseline is modified, they lose points AND it suggests they didn't use Parametric Run correctly
        feedback_parts.append("Baseline glass types appear modified (Destructive editing detected)")
        # Penalize: if they modified baseline, they likely fail the "Parametric Run" goal
        # The score logic naturally handles this since they might get points for #2/#3 if they created a run 
        # but ALSO modified baseline? No, usually mutually exclusive in intent. 
        # If they just edited the tree, 'run_command_found' would likely be false.

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }