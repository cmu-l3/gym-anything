#!/usr/bin/env python3
"""
Verifier for Benchmark Optimization task
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_benchmark_optimization(traj, env_info, task_info):
    """
    Verify the benchmark optimization task was completed correctly.
    
    Checks:
    1. benchmark_report.txt exists with required content
    2. Both timing measurements present and valid
    3. Output verification was performed
    4. Decision was documented
    5. Code reflects correct decision (if optimized faster AND correct, should be kept)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='benchmark_verify_')
    
    try:
        repo_path = "/home/ga/workspace/benchmark_task"
        
        # Copy benchmark report
        report_path = os.path.join(repo_path, "benchmark_report.txt")
        local_report = os.path.join(temp_dir, "benchmark_report.txt")
        
        try:
            copy_from_env(report_path, local_report)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ benchmark_report.txt not found: {str(e)}"
            }
        
        if not os.path.exists(local_report) or os.path.getsize(local_report) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ benchmark_report.txt is empty or doesn't exist"
            }
        
        # Read report content
        with open(local_report, 'r') as f:
            report_content = f.read()
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # Criterion 1: Extract timing values
        original_time_match = re.search(r'Original Time:\s*(\d+\.?\d*)', report_content, re.IGNORECASE)
        optimized_time_match = re.search(r'Optimized Time:\s*(\d+\.?\d*)', report_content, re.IGNORECASE)
        
        if not original_time_match or not optimized_time_match:
            feedback_parts.append("❌ Missing timing measurements in report")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        try:
            original_time = float(original_time_match.group(1))
            optimized_time = float(optimized_time_match.group(1))
        except ValueError:
            feedback_parts.append("❌ Invalid timing values in report")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        if original_time <= 0 or optimized_time <= 0:
            feedback_parts.append("❌ Timing values must be positive")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria_passed += 1
        feedback_parts.append(f"✅ Valid timing measurements: Original={original_time:.3f}s, Optimized={optimized_time:.3f}s")
        
        # Criterion 2: Check if timings are different (proves both were run)
        if abs(original_time - optimized_time) < 0.001:
            feedback_parts.append("⚠️ Warning: Times are identical (did you run both versions?)")
        else:
            criteria_passed += 1
            feedback_parts.append("✅ Different timing values detected (both versions run)")
        
        # Criterion 3: Check output verification was performed
        verification_patterns = [
            r'Output Verification:\s*(PASS|FAIL)',
            r'Output.*match',
            r'Correctness.*verified',
            r'Output.*identical',
            r'Verification:\s*(PASS|FAIL)'
        ]
        
        verification_found = False
        output_verified_pass = False
        
        for pattern in verification_patterns:
            match = re.search(pattern, report_content, re.IGNORECASE)
            if match:
                verification_found = True
                if 'PASS' in match.group(0).upper() or 'match' in match.group(0).lower() or 'identical' in match.group(0).lower():
                    output_verified_pass = True
                break
        
        if verification_found:
            criteria_passed += 1
            status = "PASS" if output_verified_pass else "FAIL/unclear"
            feedback_parts.append(f"✅ Output verification performed: {status}")
        else:
            feedback_parts.append("❌ No explicit output verification mentioned")
        
        # Criterion 4: Check decision was documented
        decision_patterns = [
            r'Decision:\s*(KEPT|REVERTED|KEEP|REVERT|OPTIMIZED|ORIGINAL)',
            r'(KEPT|REVERTED|KEEPING|REVERTING)',
        ]
        
        decision_found = False
        decision_text = ""
        
        for pattern in decision_patterns:
            match = re.search(pattern, report_content, re.IGNORECASE)
            if match:
                decision_found = True
                decision_text = match.group(0)
                break
        
        if decision_found:
            criteria_passed += 1
            feedback_parts.append(f"✅ Decision documented: {decision_text}")
        else:
            feedback_parts.append("❌ No decision documented in report")
        
        # Criterion 5: Verify data_processor.py reflects correct decision
        processor_path = os.path.join(repo_path, "data_processor.py")
        local_processor = os.path.join(temp_dir, "data_processor.py")
        
        try:
            copy_from_env(processor_path, local_processor)
        except Exception as e:
            feedback_parts.append(f"❌ Cannot access data_processor.py: {str(e)}")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        with open(local_processor, 'r') as f:
            processor_content = f.read()
        
        # Check if optimized version is present (uses sum() and list comprehension)
        has_sum_builtin = 'sum(data)' in processor_content or 'sum(record' in processor_content
        has_list_comp = '[v * avg for v in' in processor_content or '[value * avg for value in' in processor_content
        is_optimized_version = has_sum_builtin and has_list_comp
        
        # Determine what the correct decision should be
        should_be_optimized = (optimized_time < original_time) and output_verified_pass
        
        # Check consistency
        if should_be_optimized and is_optimized_version:
            criteria_passed += 1
            feedback_parts.append("✅ Correct: Optimized version kept (faster and correct)")
        elif should_be_optimized and not is_optimized_version:
            feedback_parts.append("❌ Error: Optimized was faster and correct but was reverted")
        elif not should_be_optimized and not is_optimized_version:
            criteria_passed += 1
            reason = "slower" if optimized_time >= original_time else "incorrect output"
            feedback_parts.append(f"✅ Correct: Original kept (optimized was {reason})")
        else:
            # Optimized kept but shouldn't have been
            if optimized_time >= original_time:
                feedback_parts.append("⚠️ Warning: Optimized version kept despite being slower")
            elif not output_verified_pass:
                feedback_parts.append("⚠️ Warning: Optimized version kept but output verification unclear")
            else:
                # Edge case: maybe acceptable
                criteria_passed += 1
                feedback_parts.append("✅ Decision made (optimized kept)")
        
        # Check for comparison artifacts (good practice)
        try:
            output_orig_path = os.path.join(repo_path, "output_original.json")
            local_output_orig = os.path.join(temp_dir, "output_original.json")
            copy_from_env(output_orig_path, local_output_orig)
            feedback_parts.append("✅ Good practice: Found output_original.json (comparison artifact)")
        except:
            pass
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # Need 4/5 criteria (80%)
        
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
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
