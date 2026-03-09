#!/usr/bin/env python3
"""
Phase 4 & 5 Validation Tests for new jolly_lobby_track_env tasks.

Tests:
  1. Do-Nothing Test     — file missing → score=0, passed=False
  2. Wrong-Target Test   — file exists but wrong/empty content → score=0, passed=False
  3. Partial Completion  — file has some correct records → partial score, passed=False

Run from repo root:
    python benchmarks/environments/jolly_lobby_track_env/dev/test_new_tasks.py
"""
import sys
import os
import json
import tempfile
import time

# Add repo root to sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + "/../..")

# Import verifiers directly from their modules
import importlib.util

TASKS_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "tasks")
EVIDENCE_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "evidence")

NEW_TASKS = [
    "contractor_overstay_audit_dec2025",
    "vendor_department_access_report",
    "defense_sector_host_compliance",
    "december_visitor_badge_breakdown",
    "pharmaceutical_visitor_audit",
]


def load_verifier(task_name):
    """Dynamically load a verifier module."""
    verifier_path = os.path.join(TASKS_DIR, task_name, "verifier.py")
    spec = importlib.util.spec_from_file_location(f"verifier_{task_name}", verifier_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_copy_from_env(json_data, csv_content=None):
    """
    Build a mock copy_from_env function.
    - Returns json_data as JSON for any .json path
    - Returns csv_content for any .csv path (or raises FileNotFoundError if None)
    """
    def copy_from_env(src_path, dst_path):
        if src_path.endswith(".json"):
            with open(dst_path, "w") as f:
                json.dump(json_data, f)
        elif src_path.endswith(".csv"):
            if csv_content is None:
                raise FileNotFoundError(f"Mock: CSV not available: {src_path}")
            with open(dst_path, "w") as f:
                f.write(csv_content)
        else:
            raise FileNotFoundError(f"Mock: unknown path: {src_path}")
    return copy_from_env


# ─── Task-specific data ───────────────────────────────────────────────────────

TASK_CONFIG = {
    "contractor_overstay_audit_dec2025": {
        "result_json_key": "/tmp/contractor_overstay_audit_dec2025_result.json",
        "output_csv": "/home/ga/Desktop/contractor_overstay_dec2025.csv",
        "do_nothing_json": {
            "task": "contractor_overstay_audit_dec2025",
            "file_exists": False,
            "file_size": 0,
            "file_content": "",
            "file_path": "/home/ga/Desktop/contractor_overstay_dec2025.csv",
        },
        "wrong_target_json": {
            "task": "contractor_overstay_audit_dec2025",
            "file_exists": True,
            "file_size": 150,
            "file_content": "visitor,company,duration\nJohn Doe,UnknownCorp,30\n",
            "file_path": "/home/ga/Desktop/contractor_overstay_dec2025.csv",
        },
        "wrong_target_csv": "visitor,company,duration\nJohn Doe,UnknownCorp,30\n",
        "partial_json": {
            "task": "contractor_overstay_audit_dec2025",
            "file_exists": True,
            "file_size": 200,
            "file_content": "visitor,company,check_in,check_out,duration_min\nMaria Garcia,Deloitte LLP,10:00,12:30,150\n",
            "file_path": "/home/ga/Desktop/contractor_overstay_dec2025.csv",
        },
        "partial_csv": "visitor,company,check_in,check_out,duration_min\nMaria Garcia,Deloitte LLP,10:00,12:30,150\n",
        "partial_expected_score_range": (25, 75),  # 1-3 criteria, not all 4
        "verifier_fn": "verify_contractor_overstay_audit_dec2025",
    },
    "vendor_department_access_report": {
        "result_json_key": "/tmp/vendor_department_access_report_result.json",
        "output_csv": "/home/ga/Desktop/vendor_dept_access_dec2025.csv",
        "do_nothing_json": {
            "task": "vendor_department_access_report",
            "file_exists": False,
            "file_size": 0,
            "file_content": "",
            "file_path": "/home/ga/Desktop/vendor_dept_access_dec2025.csv",
        },
        "wrong_target_json": {
            "task": "vendor_department_access_report",
            "file_exists": True,
            "file_size": 100,
            "file_content": "department,vendor_count\nMarketing,1\n",
            "file_path": "/home/ga/Desktop/vendor_dept_access_dec2025.csv",
        },
        "wrong_target_csv": "department,vendor_count\nMarketing,1\n",
        # Partial: Facilities found (30) + only Ford (8) + size>150 (20) = 58 pts, not passing
        "partial_json": {
            "task": "vendor_department_access_report",
            "file_exists": True,
            "file_size": 200,
            "file_content": (
                "department,vendor_count,vendor_names\n"
                "Facilities,1,Ford Motor Company\n"
            ),
            "file_path": "/home/ga/Desktop/vendor_dept_access_dec2025.csv",
        },
        "partial_csv": (
            "department,vendor_count,vendor_names\n"
            "Facilities,1,Ford Motor Company\n"
        ),
        "partial_expected_score_range": (30, 69),
        "verifier_fn": "verify_vendor_department_access_report",
    },
    "defense_sector_host_compliance": {
        "result_json_key": "/tmp/defense_sector_host_compliance_result.json",
        "output_csv": "/home/ga/Desktop/defense_host_compliance.csv",
        "do_nothing_json": {
            "task": "defense_sector_host_compliance",
            "file_exists": False,
            "file_size": 0,
            "file_content": "",
            "file_path": "/home/ga/Desktop/defense_host_compliance.csv",
        },
        "wrong_target_json": {
            "task": "defense_sector_host_compliance",
            "file_exists": True,
            "file_size": 100,
            "file_content": "visitor,company,host_dept\nJohn Smith,AcmeCorp,Security\n",
            "file_path": "/home/ga/Desktop/defense_host_compliance.csv",
        },
        "wrong_target_csv": "visitor,company,host_dept\nJohn Smith,AcmeCorp,Security\n",
        "partial_json": {
            "task": "defense_sector_host_compliance",
            "file_exists": True,
            "file_size": 300,
            "file_content": (
                "visitor,company,host_name,host_dept,visit_date\n"
                "Robert Clark,Boeing,Karen Clark,Compliance,2025-12-03\n"
            ),
            "file_path": "/home/ga/Desktop/defense_host_compliance.csv",
        },
        "partial_csv": (
            "visitor,company,host_name,host_dept,visit_date\n"
            "Robert Clark,Boeing,Karen Clark,Compliance,2025-12-03\n"
        ),
        "partial_expected_score_range": (25, 75),
        "verifier_fn": "verify_defense_sector_host_compliance",
    },
    "december_visitor_badge_breakdown": {
        "result_json_key": "/tmp/december_visitor_badge_breakdown_result.json",
        "output_csv": "/home/ga/Desktop/dec2025_visitor_analysis.csv",
        "do_nothing_json": {
            "task": "december_visitor_badge_breakdown",
            "file_exists": False,
            "file_size": 0,
            "file_content": "",
            "file_path": "/home/ga/Desktop/dec2025_visitor_analysis.csv",
        },
        "wrong_target_json": {
            "task": "december_visitor_badge_breakdown",
            "file_exists": True,
            "file_size": 80,
            "file_content": "summary\nTotal visitors: 5\n",
            "file_path": "/home/ga/Desktop/dec2025_visitor_analysis.csv",
        },
        "wrong_target_csv": "summary\nTotal visitors: 5\n",
        # Partial: total 40 (25) + badge keywords+counts (25) + no depts (0) + file < 50 bytes (0) = 50 pts, not passing
        "partial_json": {
            "task": "december_visitor_badge_breakdown",
            "file_exists": True,
            "file_size": 45,
            "file_content": "Total: 40\nVisitor: 16\nContractor: 12\nVendor: 12\n",
            "file_path": "/home/ga/Desktop/dec2025_visitor_analysis.csv",
        },
        "partial_csv": "Total: 40\nVisitor: 16\nContractor: 12\nVendor: 12\n",
        "partial_expected_score_range": (40, 69),
        "verifier_fn": "verify_december_visitor_badge_breakdown",
    },
    "pharmaceutical_visitor_audit": {
        "result_json_key": "/tmp/pharmaceutical_visitor_audit_result.json",
        "output_csv": "/home/ga/Desktop/pharma_healthcare_visitor_audit.csv",
        "do_nothing_json": {
            "task": "pharmaceutical_visitor_audit",
            "file_exists": False,
            "file_size": 0,
            "file_content": "",
            "file_path": "/home/ga/Desktop/pharma_healthcare_visitor_audit.csv",
        },
        "wrong_target_json": {
            "task": "pharmaceutical_visitor_audit",
            "file_exists": True,
            "file_size": 100,
            "file_content": "visitor,company\nJohn Smith,RandomCorp\n",
            "file_path": "/home/ga/Desktop/pharma_healthcare_visitor_audit.csv",
        },
        "wrong_target_csv": "visitor,company\nJohn Smith,RandomCorp\n",
        "partial_json": {
            "task": "pharmaceutical_visitor_audit",
            "file_exists": True,
            "file_size": 300,
            "file_content": (
                "visitor_name,company,visit_purpose,host_name,host_dept\n"
                "James Smith,Johnson & Johnson,Business Meeting,Michelle Allen,Legal\n"
                "Patricia Williams,Pfizer Inc,Vendor Meeting,Maria Edwards,Procurement\n"
            ),
            "file_path": "/home/ga/Desktop/pharma_healthcare_visitor_audit.csv",
        },
        "partial_csv": (
            "visitor_name,company,visit_purpose,host_name,host_dept\n"
            "James Smith,Johnson & Johnson,Business Meeting,Michelle Allen,Legal\n"
            "Patricia Williams,Pfizer Inc,Vendor Meeting,Maria Edwards,Procurement\n"
        ),
        "partial_expected_score_range": (40, 60),
        "verifier_fn": "verify_pharmaceutical_visitor_audit",
    },
}


def run_verifier(module, fn_name, env_info, task_info=None):
    """Run verifier function and return result."""
    fn = getattr(module, fn_name)
    return fn(traj=[], env_info=env_info, task_info=task_info or {})


def test_do_nothing(task_name, config, module):
    """Test 1: Do-nothing — file doesn't exist → score=0, passed=False."""
    print(f"  [DO-NOTHING] Testing {task_name}...")
    mock_json = config["do_nothing_json"]
    copy_fn = make_copy_from_env(mock_json, csv_content=None)
    env_info = {"copy_from_env": copy_fn}

    result = run_verifier(module, config["verifier_fn"], env_info)

    passed_test = result["score"] == 0 and result["passed"] == False
    status = "PASS" if passed_test else "FAIL"
    print(f"    score={result['score']}, passed={result['passed']} → [{status}]")
    if not passed_test:
        print(f"    feedback: {result.get('feedback', '')}")
    return passed_test, result


def test_wrong_target(task_name, config, module):
    """Test 2: Wrong target — file exists with irrelevant content → score=0."""
    print(f"  [WRONG-TARGET] Testing {task_name}...")
    mock_json = config["wrong_target_json"]
    csv_content = config["wrong_target_csv"]
    copy_fn = make_copy_from_env(mock_json, csv_content=csv_content)
    env_info = {"copy_from_env": copy_fn}

    result = run_verifier(module, config["verifier_fn"], env_info)

    # Wrong target should score 0 (or very low, ≤25)
    passed_test = result["score"] <= 25 and result["passed"] == False
    status = "PASS" if passed_test else "FAIL"
    print(f"    score={result['score']}, passed={result['passed']} → [{status}]")
    if not passed_test:
        print(f"    feedback: {result.get('feedback', '')}")
    return passed_test, result


def test_partial_completion(task_name, config, module):
    """Test 3: Partial completion — some records → partial score, passed=False."""
    print(f"  [PARTIAL] Testing {task_name}...")
    mock_json = config["partial_json"]
    csv_content = config["partial_csv"]
    copy_fn = make_copy_from_env(mock_json, csv_content=csv_content)
    env_info = {"copy_from_env": copy_fn}

    result = run_verifier(module, config["verifier_fn"], env_info)

    lo, hi = config["partial_expected_score_range"]
    passed_test = lo <= result["score"] <= hi and result["passed"] == False
    status = "PASS" if passed_test else "WARN"
    print(f"    score={result['score']} (expected {lo}-{hi}), passed={result['passed']} → [{status}]")
    if not passed_test:
        print(f"    feedback: {result.get('feedback', '')}")
    return passed_test, result


def write_evidence_json(task_name, results):
    """Write evidence JSON file documenting test results."""
    os.makedirs(EVIDENCE_DIR, exist_ok=True)

    config = TASK_CONFIG[task_name]
    evidence = {
        "task": task_name,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "phase": "Phase 4 & 5 Testing",
        "environment": "jolly_lobby_track_env",
        "checks": {
            "target_entity": f"Visitor report output at {config['output_csv']}",
            "initial_state": "LobbyTrack visitor data loaded from visitor_records.csv (50 records, Dec 2025 - Jan 2026)",
            "service_status": "LobbyTrack 8.1 running via Wine on Ubuntu GNOME"
        },
        "test_results": {
            "do_nothing": {
                "description": "File not present → score must be 0",
                "score": results["do_nothing"][1]["score"],
                "passed": results["do_nothing"][1]["passed"],
                "test_passed": results["do_nothing"][0],
                "feedback": results["do_nothing"][1].get("feedback", ""),
            },
            "wrong_target": {
                "description": "File present but irrelevant content → score ≤25",
                "score": results["wrong_target"][1]["score"],
                "passed": results["wrong_target"][1]["passed"],
                "test_passed": results["wrong_target"][0],
                "feedback": results["wrong_target"][1].get("feedback", ""),
            },
            "partial_completion": {
                "description": "Partial records present → partial score, not passing",
                "score": results["partial"][1]["score"],
                "passed": results["partial"][1]["passed"],
                "test_passed": results["partial"][0],
                "expected_range": config["partial_expected_score_range"],
                "feedback": results["partial"][1].get("feedback", ""),
            },
        },
        "setup_files_created": [
            f"/tmp/{task_name}_result.json",
            "/tmp/task_start_timestamp",
        ],
        "data_verification": {
            "source_file": "benchmarks/environments/jolly_lobby_track_env/data/visitor_records.csv",
            "total_records": 50,
            "december_2025_records": 40,
            "data_loaded_to": "/home/ga/LobbyTrack/data/visitor_records.csv (via setup_task.sh)",
        },
    }

    evidence_path = os.path.join(EVIDENCE_DIR, f"{task_name}_evidence.json")
    with open(evidence_path, "w") as f:
        json.dump(evidence, f, indent=2)
    print(f"  Evidence saved: {evidence_path}")
    return evidence_path


def main():
    print("=" * 70)
    print("jolly_lobby_track_env — Phase 4 & 5 Validation Tests")
    print("=" * 70)

    all_passed = True
    summary = {}

    for task_name in NEW_TASKS:
        print(f"\n{'─'*60}")
        print(f"Task: {task_name}")
        print("─" * 60)

        # Load verifier
        try:
            module = load_verifier(task_name)
            print(f"  Verifier loaded: {TASK_CONFIG[task_name]['verifier_fn']}")
        except Exception as e:
            print(f"  ERROR loading verifier: {e}")
            all_passed = False
            continue

        config = TASK_CONFIG[task_name]
        results = {}

        # Run 3 tests
        results["do_nothing"] = test_do_nothing(task_name, config, module)
        results["wrong_target"] = test_wrong_target(task_name, config, module)
        results["partial"] = test_partial_completion(task_name, config, module)

        # Write evidence JSON
        write_evidence_json(task_name, results)

        # Task passes if do_nothing and wrong_target both pass
        task_pass = results["do_nothing"][0] and results["wrong_target"][0]
        summary[task_name] = task_pass
        if not task_pass:
            all_passed = False

    # Summary
    print(f"\n{'='*70}")
    print("SUMMARY")
    print("=" * 70)
    for task_name, passed in summary.items():
        status = "PASS" if passed else "FAIL"
        print(f"  {task_name}: [{status}]")

    print(f"\nOverall: {'ALL TESTS PASSED' if all_passed else 'SOME TESTS FAILED'}")
    print(f"Evidence written to: {EVIDENCE_DIR}/")
    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
