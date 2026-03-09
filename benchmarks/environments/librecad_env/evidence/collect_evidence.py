#!/usr/bin/env python3
"""
Evidence collection and do-nothing testing for librecad_env tasks.

Tests:
1. Environment starts correctly (setup_task.sh runs)
2. Export script produces valid JSON (do-nothing baseline)
3. Verifier returns score=0 when nothing done
4. Screenshots captured for evidence

Run from repo root:
    python benchmarks/environments/librecad_env/evidence/collect_evidence.py
"""

import sys
import os
import time
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + '/../../..')
from gym_anything.api import from_config

EVIDENCE_DIR = 'benchmarks/environments/librecad_env/evidence'
ENV_PATH = 'benchmarks/environments/librecad_env'

NEW_TASKS = [
    'as_built_markup',
    'sheet_title_block',
    'hvac_system_overlay',
    'survey_boundary_overlay',
    'electrical_panel_schedule',
]


def collect_evidence_for_task(task_name):
    """Load environment, run do-nothing test, capture evidence."""
    print(f"\n{'='*60}")
    print(f"TESTING: {task_name}")
    print('='*60)

    evidence = {
        "task": task_name,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "checks": {}
    }

    env = from_config(ENV_PATH, task_id=task_name)

    try:
        print("  Resetting environment (runs setup_task.sh)...")
        obs = env.reset(seed=42, use_cache=False)
        print(f"  Environment ready. VNC port: {env._runner.vnc_port}")

        # 1. Check setup files were created
        print("  Checking setup files...")
        setup_files = env._runner.exec_capture(
            'ls -la /tmp/task_start_timestamp '
            f'/tmp/{task_name}_baseline.json '
            f'/tmp/{task_name}_start.png 2>&1'
        )
        evidence["checks"]["setup_files"] = setup_files.strip()
        print(f"  Setup files:\n{setup_files}")

        # 2. Check baseline JSON content
        baseline_raw = env._runner.exec_capture(
            f'cat /tmp/{task_name}_baseline.json 2>/dev/null || echo "NOT FOUND"'
        )
        try:
            baseline = json.loads(baseline_raw.strip())
            evidence["checks"]["baseline_entity_count"] = baseline.get("entity_count", "MISSING")
            evidence["checks"]["baseline_layer_count"] = len(baseline.get("layer_names", []))
            print(f"  Baseline: {baseline.get('entity_count')} entities, "
                  f"{len(baseline.get('layer_names',[]))} layers")
        except Exception:
            evidence["checks"]["baseline_json"] = f"PARSE ERROR: {baseline_raw[:200]}"
            print(f"  Baseline parse error: {baseline_raw[:200]}")

        # 3. Check source file exists
        src_size = env._runner.exec_capture(
            'stat -c%s /home/ga/Documents/LibreCAD/floorplan.dxf 2>/dev/null || echo 0'
        ).strip()
        evidence["checks"]["source_file_size"] = int(src_size) if src_size.isdigit() else 0
        print(f"  Source DXF size: {src_size} bytes")

        # 4. Take screenshot of initial state
        print("  Capturing initial screenshot...")
        env._runner.exec_capture(
            'DISPLAY=:1 import -window root /tmp/task_start_screenshot.png 2>/dev/null || true'
        )
        time.sleep(1)
        screenshot_path = f'{EVIDENCE_DIR}/{task_name}_screenshot.png'
        try:
            env._runner.copy_from('/tmp/task_start_screenshot.png', screenshot_path)
            evidence["screenshot"] = screenshot_path
            print(f"  Screenshot saved: {screenshot_path}")
        except Exception as e:
            print(f"  Screenshot error: {e}")
            evidence["screenshot_error"] = str(e)

        # 5. Run export script (do-nothing test)
        print("  Running export script (do-nothing test)...")
        export_out = env._runner.exec_capture(
            f'bash /workspace/tasks/{task_name}/export_result.sh 2>&1'
        )
        print(f"  Export output (last 500 chars):\n{export_out[-500:]}")
        evidence["checks"]["export_completed"] = "export complete" in export_out.lower()

        # 6. Read and validate result JSON
        result_raw = env._runner.exec_capture(
            f'cat /tmp/{task_name}_result.json 2>/dev/null || echo "NOT FOUND"'
        )
        if result_raw.strip() == "NOT FOUND":
            evidence["checks"]["result_json"] = "NOT FOUND"
            print("  Result JSON: NOT FOUND")
        else:
            try:
                result_json = json.loads(result_raw)
                evidence["checks"]["result_json_valid"] = True
                evidence["checks"]["output_file_exists"] = result_json.get(
                    "output_file_exists", result_json.get("output_exists", False)
                )
                print(f"  Result JSON valid. output_file_exists="
                      f"{evidence['checks']['output_file_exists']}")

                # Copy result JSON locally
                local_result = f'{EVIDENCE_DIR}/{task_name}_result_donoting.json'
                with open(local_result, 'w') as f:
                    json.dump(result_json, f, indent=2)
                evidence["result_json_path"] = local_result
                print(f"  Result JSON saved: {local_result}")
            except json.JSONDecodeError as e:
                evidence["checks"]["result_json_valid"] = False
                evidence["checks"]["result_json_error"] = str(e)
                evidence["checks"]["result_json_raw"] = result_raw[:500]
                print(f"  Result JSON PARSE ERROR: {e}")

        # 7. Run do-nothing verification (mark_done=True without any actions)
        print("  Running do-nothing verification...")
        try:
            obs2, reward, done, info = env.step([], mark_done=True)
            verifier_result = info.get("verifier", {})
            evidence["do_nothing_score"] = verifier_result.get("score", "ERROR")
            evidence["do_nothing_passed"] = verifier_result.get("passed", "ERROR")
            evidence["do_nothing_feedback"] = verifier_result.get("feedback", "")[:200]
            print(f"  Do-nothing score: {verifier_result.get('score')}/100, "
                  f"passed: {verifier_result.get('passed')}")
            print(f"  Feedback: {verifier_result.get('feedback', '')[:200]}")

            # Verify score is 0
            score = verifier_result.get("score", -1)
            passed = verifier_result.get("passed", True)
            if score == 0 and not passed:
                evidence["do_nothing_test"] = "PASS (score=0, passed=False as expected)"
                print(f"  [PASS] Do-nothing test: score=0, passed=False")
            else:
                evidence["do_nothing_test"] = f"FAIL (score={score}, passed={passed})"
                print(f"  [FAIL] Do-nothing test: score={score}, passed={passed}")
        except Exception as e:
            evidence["do_nothing_error"] = str(e)
            print(f"  Verification error: {e}")

    except Exception as e:
        evidence["error"] = str(e)
        print(f"  ERROR: {e}")
        import traceback
        traceback.print_exc()
    finally:
        env.close()

    # Save evidence JSON
    evidence_path = f'{EVIDENCE_DIR}/{task_name}_evidence.json'
    with open(evidence_path, 'w') as f:
        json.dump(evidence, f, indent=2)
    print(f"  Evidence saved: {evidence_path}")

    return evidence


if __name__ == "__main__":
    os.makedirs(EVIDENCE_DIR, exist_ok=True)

    all_results = {}

    for task in NEW_TASKS:
        result = collect_evidence_for_task(task)
        all_results[task] = result

    print(f"\n{'='*60}")
    print("EVIDENCE COLLECTION SUMMARY")
    print('='*60)
    for task, evidence in all_results.items():
        score = evidence.get("do_nothing_score", "N/A")
        passed = evidence.get("do_nothing_passed", "N/A")
        test_result = evidence.get("do_nothing_test", "N/A")
        print(f"  {task}: do-nothing score={score}, passed={passed} → {test_result}")

    print(f"\nAll evidence saved to: {EVIDENCE_DIR}/")
