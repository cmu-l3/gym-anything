#!/usr/bin/env python3
"""
Verifier for Experiment Compiler Flags task
"""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compiler_flags(traj, env_info, task_info):
    """
    Verify that tasks.json contains multiple build configurations with different
    optimization flags for compiler experimentation.
    
    Checks:
    1. tasks.json exists and is valid JSON (20%)
    2. Contains at least 4 tasks (15%)
    3. All required optimization flags present: -O0, -O2, -O3, -Ofast (25%)
    4. Output files are differentiated (20%)
    5. Tasks have unique descriptive labels (10%)
    6. Tasks compile benchmark.cpp (10%)
    
    Pass threshold: 80%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Copy tasks.json from /tmp (exported by export_result.sh)
        tasks_path = "/tmp/tasks.json"
        
        try:
            copy_from_env(tasks_path, temp_file.name)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"tasks.json not found or not copied: {str(e)}"
            }
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "tasks.json not found or empty at /home/ga/workspace/performance_test/.vscode/tasks.json"
            }
        
        # Parse JSON
        try:
            with open(temp_file.name, 'r', encoding='utf-8') as f:
                tasks_config = json.load(f)
        except json.JSONDecodeError as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Invalid JSON in tasks.json: {str(e)}"
            }
        
        score = 0.0
        feedback_parts = []
        
        # Criterion 1: Valid JSON with tasks array (20%)
        if 'tasks' not in tasks_config:
            return {
                "passed": False,
                "score": 0,
                "feedback": "tasks.json missing 'tasks' array"
            }
        
        tasks = tasks_config.get('tasks', [])
        if not isinstance(tasks, list):
            return {
                "passed": False,
                "score": 0,
                "feedback": "'tasks' must be an array"
            }
        
        score += 20
        feedback_parts.append(f"✅ Valid JSON with tasks array")
        
        # Criterion 2: At least 4 tasks (15%)
        num_tasks = len(tasks)
        if num_tasks >= 4:
            score += 15
            feedback_parts.append(f"✅ Found {num_tasks} tasks (required: 4+)")
        elif num_tasks >= 3:
            score += 10
            feedback_parts.append(f"⚠️ Found {num_tasks} tasks (expected 4+)")
        elif num_tasks >= 2:
            score += 5
            feedback_parts.append(f"❌ Only {num_tasks} tasks (need at least 4)")
        else:
            feedback_parts.append(f"❌ Insufficient tasks: {num_tasks} (need 4+)")
        
        # Criterion 3: Check for all required optimization flags (25%)
        required_flags = {
            '-O0': False,
            '-O2': False,
            '-O3': False,
            '-Ofast': False
        }
        
        output_names = []
        labels = []
        compiles_benchmark = False
        uses_gpp = False
        
        for task in tasks:
            # Get command and args
            command = task.get('command', '')
            args = task.get('args', [])
            
            # Convert args to string if list
            if isinstance(args, list):
                args_str = ' '.join(str(arg) for arg in args)
            else:
                args_str = str(args)
            
            full_command = f"{command} {args_str}"
            
            # Check optimization flags
            for flag in required_flags.keys():
                if flag in full_command or flag in args_str:
                    required_flags[flag] = True
            
            # Check for g++/gcc
            if 'g++' in command.lower() or 'gcc' in command.lower():
                uses_gpp = True
            
            # Check for benchmark.cpp
            if 'benchmark.cpp' in full_command or 'benchmark.cpp' in args_str:
                compiles_benchmark = True
            
            # Extract output filename
            if isinstance(args, list):
                for i, arg in enumerate(args):
                    if arg == '-o' and i + 1 < len(args):
                        output_names.append(str(args[i + 1]))
                    elif str(arg).startswith('-o'):
                        output_names.append(str(arg)[2:])
            
            # Collect labels
            if 'label' in task:
                labels.append(task['label'])
        
        # Score optimization flags
        flags_found = sum(required_flags.values())
        if flags_found == 4:
            score += 25
            feedback_parts.append("✅ All optimization flags present (-O0, -O2, -O3, -Ofast)")
        elif flags_found == 3:
            score += 18
            missing = [k for k, v in required_flags.items() if not v]
            feedback_parts.append(f"⚠️ Missing flag(s): {', '.join(missing)}")
        elif flags_found == 2:
            score += 12
            missing = [k for k, v in required_flags.items() if not v]
            feedback_parts.append(f"❌ Missing flags: {', '.join(missing)}")
        else:
            found = [k for k, v in required_flags.items() if v]
            feedback_parts.append(f"❌ Only found {flags_found}/4 flags: {', '.join(found) if found else 'none'}")
        
        # Criterion 4: Output differentiation (20%)
        unique_outputs = len(set(output_names))
        if unique_outputs >= 4 and len(output_names) >= 4:
            # Check if output names contain optimization indicators
            has_o_indicators = sum(
                1 for name in output_names
                if any(opt.replace('-', '').lower() in name.lower() for opt in ['-O0', '-O2', '-O3', '-Ofast'])
            )
            if has_o_indicators >= 3:
                score += 20
                feedback_parts.append("✅ Output files properly differentiated")
            else:
                score += 15
                feedback_parts.append("⚠️ Output files unique but should include optimization level in name")
        elif unique_outputs >= 3:
            score += 12
            feedback_parts.append("⚠️ Some output files not unique")
        elif unique_outputs >= 2:
            score += 6
            feedback_parts.append("❌ Most output files not differentiated")
        else:
            feedback_parts.append("❌ Output files not properly differentiated")
        
        # Criterion 5: Unique descriptive labels (10%)
        if len(labels) >= 4 and len(set(labels)) == len(labels):
            score += 10
            feedback_parts.append("✅ All tasks have unique descriptive labels")
        elif len(labels) >= 3:
            score += 6
            if len(set(labels)) < len(labels):
                feedback_parts.append("⚠️ Some task labels are duplicated")
            else:
                feedback_parts.append("⚠️ Missing labels on some tasks")
        else:
            feedback_parts.append("❌ Tasks need unique descriptive labels")
        
        # Criterion 6: Compiles benchmark.cpp (10%)
        if compiles_benchmark and uses_gpp:
            score += 10
            feedback_parts.append("✅ Tasks compile benchmark.cpp with g++")
        elif compiles_benchmark:
            score += 5
            feedback_parts.append("⚠️ Tasks compile benchmark.cpp (but check compiler)")
        elif uses_gpp:
            score += 3
            feedback_parts.append("❌ Uses g++ but not compiling benchmark.cpp")
        else:
            feedback_parts.append("❌ Tasks should compile benchmark.cpp with g++")
        
        # Normalize score to 0-100
        score = min(100, int(score))
        passed = score >= 80
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
