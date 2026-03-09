#!/usr/bin/env python3
"""
Phase 5 Validation Tests for all 5 new OpenCAD tasks.
Tests wrong-target and partial-completion scenarios without requiring a live VM.

Each verifier reads from a JSON injected via copy_from_env mock.
"""

import json
import sys
import os
import tempfile

# Add the project root to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..')))

from examples.opencad_env.tasks.fugitive_traffic_stop.verifier import verify_fugitive_traffic_stop
from examples.opencad_env.tasks.armed_robbery_response.verifier import verify_armed_robbery_response
from examples.opencad_env.tasks.new_resident_full_processing.verifier import verify_new_resident_full_processing
from examples.opencad_env.tasks.major_incident_documentation.verifier import verify_major_incident_documentation
from examples.opencad_env.tasks.multi_jurisdiction_pursuit.verifier import verify_multi_jurisdiction_pursuit


def make_copy_from_env(injected_result: dict):
    """Return a mock copy_from_env that writes injected_result to dest_path."""
    def copy_from_env(src_path: str, dest_path: str):
        with open(dest_path, 'w') as f:
            json.dump(injected_result, f)
    return copy_from_env


def run_test(name, verify_fn, injected_result, task_info,
             expected_pass, expected_score_range, description):
    """Run a single verifier test. Returns (test_name, passed, details)."""
    env_info = {'copy_from_env': make_copy_from_env(injected_result)}
    result = verify_fn([], env_info, task_info)

    actual_score = result.get('score', -1)
    actual_pass = result.get('passed', None)

    score_min, score_max = expected_score_range
    score_ok = score_min <= actual_score <= score_max
    pass_ok = actual_pass == expected_pass

    test_pass = score_ok and pass_ok
    status = "PASS" if test_pass else "FAIL"

    print(f"  [{status}] {name}")
    print(f"         score={actual_score} (expected {score_min}-{score_max}), passed={actual_pass} (expected {expected_pass})")
    if not test_pass:
        print(f"         feedback: {result.get('feedback', '')}")

    return {
        "test_name": name,
        "description": description,
        "status": status,
        "actual_score": actual_score,
        "actual_passed": actual_pass,
        "expected_score_range": [score_min, score_max],
        "expected_passed": expected_pass,
        "feedback": result.get('feedback', '')
    }


def main():
    results = []

    # =========================================================================
    # TASK 1: fugitive_traffic_stop
    # =========================================================================
    print("\n=== Task: fugitive_traffic_stop ===")
    task_info_fts = {
        "metadata": {
            "expected_call_type": "10-38",
            "expected_street1": "Forum Drive",
            "expected_street2": "Strawberry Avenue",
            "expected_citation_person": "Franklin Clinton",
            "expected_citation_name_id": 2,
            "expected_citation_name": "Running Red Light",
            "expected_fine": 175.00
        }
    }

    # Wrong-target test: citation for wrong person (name_id=99)
    wrong_target_fts = {
        "call_found": True,
        "call": {
            "type": "10-38 Traffic Stop",
            "street1": "Forum Drive",
            "street2": "Strawberry Avenue",
            "narrative": "Traffic stop in progress"
        },
        "citation_found": True,
        "franklin_citation_found": False,
        "citation": {
            "name_id": 99,
            "citation_name": "Running Red Light",
            "fine": 175.00
        },
        "bolo_person_found": False,
        "bolo_person": {}
    }
    results.append(run_test(
        "fugitive_traffic_stop: wrong-target citation (name_id=99 instead of Franklin=2)",
        verify_fugitive_traffic_stop, wrong_target_fts, task_info_fts,
        expected_pass=False, expected_score_range=(30, 40),
        description="Citation for wrong person should zero citation section (45 pts). Call (35) OK."
    ))

    # Partial completion test: only call created (no citation, no BOLO)
    partial_fts = {
        "call_found": True,
        "call": {
            "type": "10-38 Traffic Stop",
            "street1": "Forum Drive",
            "street2": "Strawberry Avenue",
            "narrative": "Traffic stop at Forum Drive and Strawberry Avenue"
        },
        "citation_found": False,
        "franklin_citation_found": False,
        "citation": {},
        "bolo_person_found": False,
        "bolo_person": {}
    }
    results.append(run_test(
        "fugitive_traffic_stop: partial (call only)",
        verify_fugitive_traffic_stop, partial_fts, task_info_fts,
        expected_pass=False, expected_score_range=(30, 40),
        description="Only call created. Score = 15+10+10 = 35 pts. Passed=False."
    ))

    # =========================================================================
    # TASK 2: armed_robbery_response
    # =========================================================================
    print("\n=== Task: armed_robbery_response ===")
    task_info_arb = {
        "metadata": {
            "expected_call_type": "10-31",
            "expected_street1": "Vinewood Boulevard",
            "expected_street2": "Hawick Avenue",
            "expected_vehicle_plate": "RPZ-7851",
            "expected_warrant_person": "Trevor Philips",
            "expected_warrant_name_id": 3
        }
    }

    # Wrong-target test: warrant for wrong person (name_id=99)
    wrong_target_arb = {
        "call_found": True,
        "call": {
            "type": "10-31 Armed Robbery",
            "street1": "Vinewood Boulevard",
            "street2": "Hawick Avenue",
            "narrative": "Armed robbery in progress"
        },
        "vehicle_bolo_found": False,
        "vehicle_bolo": {},
        "person_bolo_found": False,
        "person_bolo": {},
        "warrant_found": True,
        "trevor_warrant_found": False,
        "warrant": {
            "name_id": 99,
            "warrant_name": "Armed Robbery"
        }
    }
    results.append(run_test(
        "armed_robbery_response: wrong-target warrant (name_id=99 instead of Trevor=3)",
        verify_armed_robbery_response, wrong_target_arb, task_info_arb,
        expected_pass=False, expected_score_range=(15, 25),
        description="Warrant for wrong person should zero warrant section (35 pts). Call (20) OK."
    ))

    # Partial completion test: call + vehicle BOLO only
    partial_arb = {
        "call_found": True,
        "call": {
            "type": "10-31 Armed Robbery",
            "street1": "Vinewood Boulevard",
            "street2": "Hawick Avenue",
            "narrative": "Armed robbery in progress at Vinewood Blvd"
        },
        "vehicle_bolo_found": True,
        "vehicle_bolo": {
            "plate": "RPZ-7851",
            "make": "Karin",
            "model": "Kuruma",
            "primary_color": "Blue"
        },
        "person_bolo_found": False,
        "person_bolo": {},
        "warrant_found": False,
        "trevor_warrant_found": False,
        "warrant": {}
    }
    results.append(run_test(
        "armed_robbery_response: partial (call + vehicle BOLO only)",
        verify_armed_robbery_response, partial_arb, task_info_arb,
        expected_pass=False, expected_score_range=(40, 50),
        description="Call (20) + Vehicle BOLO (25) = 45 pts. Passed=False."
    ))

    # =========================================================================
    # TASK 3: new_resident_full_processing
    # =========================================================================
    print("\n=== Task: new_resident_full_processing ===")
    task_info_nrfp = {
        "metadata": {
            "expected_first_name": "Lamar",
            "expected_last_name": "Davis",
            "expected_dob": "1988-09-05",
            "expected_plate": "LAM-8844",
            "expected_warrant_name": "Receiving Stolen Property"
        }
    }

    # Wrong-target test: civilian with wrong name
    wrong_target_nrfp = {
        "civilian_found": True,
        "civilian": {
            "name": "John Doe",
            "dob": "1988-09-05",
            "gender": "Male",
            "race": "Black or African American"
        },
        "vehicle_found": False,
        "vehicle": {},
        "vehicle_linked_to_civilian": False,
        "warrant_found": True,
        "warrant": {
            "warrant_name": "Receiving Stolen Property",
            "issuing_agency": "Blaine County Sheriff Office"
        }
    }
    results.append(run_test(
        "new_resident_full_processing: wrong-target civilian (John Doe instead of Lamar Davis)",
        verify_new_resident_full_processing, wrong_target_nrfp, task_info_nrfp,
        expected_pass=False, expected_score_range=(0, 0),
        description="Wrong name triggers wrong-target gate -> total score = 0."
    ))

    # Partial completion test: civilian only (no vehicle, no warrant)
    partial_nrfp = {
        "civilian_found": True,
        "civilian": {
            "name": "Lamar Davis",
            "dob": "1988-09-05",
            "gender": "Male",
            "race": "Black or African American"
        },
        "vehicle_found": False,
        "vehicle": {},
        "vehicle_linked_to_civilian": False,
        "warrant_found": False,
        "warrant": {}
    }
    results.append(run_test(
        "new_resident_full_processing: partial (civilian only, no vehicle, no warrant)",
        verify_new_resident_full_processing, partial_nrfp, task_info_nrfp,
        expected_pass=False, expected_score_range=(23, 27),
        description="Civilian (15+7+3=25 pts). No vehicle, no warrant. Passed=False."
    ))

    # Partial completion test: civilian + vehicle linked (no warrant)
    partial_nrfp_2 = {
        "civilian_found": True,
        "civilian": {
            "name": "Lamar Davis",
            "dob": "1988-09-05",
            "gender": "Male",
            "race": "Black or African American"
        },
        "vehicle_found": True,
        "vehicle": {
            "plate": "LAM-8844",
            "make": "Bravado",
            "model": "Baller"
        },
        "vehicle_linked_to_civilian": True,
        "warrant_found": False,
        "warrant": {}
    }
    results.append(run_test(
        "new_resident_full_processing: partial (civilian + vehicle, no warrant)",
        verify_new_resident_full_processing, partial_nrfp_2, task_info_nrfp,
        expected_pass=False, expected_score_range=(58, 62),
        description="Civilian (25) + Vehicle (10+15+10=35) = 60 pts. Passed=False."
    ))

    # =========================================================================
    # TASK 4: major_incident_documentation
    # =========================================================================
    print("\n=== Task: major_incident_documentation ===")
    task_info_mid = {
        "metadata": {
            "expected_call_type": "10-70",
            "expected_street1": "El Rancho Boulevard",
            "expected_street2": "Jamestown Street",
            "expected_fine": 2500.00
        }
    }

    # Wrong-target test: citation for wrong person (not Michael De Santa)
    wrong_target_mid = {
        "call_found": True,
        "call": {
            "type": "10-70 Structure Fire",
            "street1": "El Rancho Boulevard",
            "street2": "Jamestown Street",
            "narrative": "Major structure fire with HAZMAT"
        },
        "citation_found": True,
        "michael_citation_found": False,
        "citation": {
            "name_id": 99,
            "citation_name": "Safety Violation",
            "fine": 2500.00
        },
        "bolo_person_found": False,
        "bolo_person": {}
    }
    results.append(run_test(
        "major_incident_documentation: wrong-target citation (name_id=99 instead of Michael=1)",
        verify_major_incident_documentation, wrong_target_mid, task_info_mid,
        expected_pass=False, expected_score_range=(28, 32),
        description="Citation for wrong person zeros citation section (45 pts). Call (30) OK."
    ))

    # Partial completion test: call + person BOLO (no citation)
    partial_mid = {
        "call_found": True,
        "call": {
            "type": "10-70 Structure Fire",
            "street1": "El Rancho Boulevard",
            "street2": "Jamestown Street",
            "narrative": "Structure fire with HAZMAT at industrial facility"
        },
        "citation_found": False,
        "michael_citation_found": False,
        "citation": {},
        "bolo_person_found": True,
        "bolo_person": {
            "physical_description": "white male, bald, heavyset, blue work jacket",
            "reason_wanted": "fled the scene of industrial explosion"
        }
    }
    results.append(run_test(
        "major_incident_documentation: partial (call + BOLO, no citation)",
        verify_major_incident_documentation, partial_mid, task_info_mid,
        expected_pass=False, expected_score_range=(53, 57),
        description="Call (30) + BOLO (15+10=25) = 55 pts. Passed=False."
    ))

    # =========================================================================
    # TASK 5: multi_jurisdiction_pursuit
    # =========================================================================
    print("\n=== Task: multi_jurisdiction_pursuit ===")
    task_info_mjp = {
        "metadata": {
            "expected_call_type": "10-80",
            "expected_street1": "Del Perro Boulevard",
            "expected_vehicle_plate": "BLC-4491",
            "expected_fine": 750.00
        }
    }

    # Wrong-target test 1: warrant for wrong person
    wrong_target_mjp_warrant = {
        "call_found": True,
        "call": {
            "type": "10-80 Pursuit",
            "street1": "Del Perro Boulevard",
            "narrative": "Vehicle pursuit crossing county lines"
        },
        "vehicle_bolo_found": False,
        "vehicle_bolo": {},
        "warrant_found": True,
        "trevor_warrant_found": False,
        "warrant": {
            "name_id": 99,
            "warrant_name": "Evading Police Officer - Felony"
        },
        "citation_found": False,
        "trevor_citation_found": False,
        "citation": {}
    }
    results.append(run_test(
        "multi_jurisdiction_pursuit: wrong-target warrant (name_id=99 instead of Trevor=3)",
        verify_multi_jurisdiction_pursuit, wrong_target_mjp_warrant, task_info_mjp,
        expected_pass=False, expected_score_range=(13, 17),
        description="Call (15) + 0 (warrant zeroed) + 0 (no citation) = 15 pts. Passed=False."
    ))

    # Wrong-target test 2: citation for wrong person (but warrant is correct)
    wrong_target_mjp_citation = {
        "call_found": True,
        "call": {
            "type": "10-80 Vehicle Pursuit",
            "street1": "Del Perro Boulevard",
            "narrative": "Multi-jurisdiction pursuit"
        },
        "vehicle_bolo_found": True,
        "vehicle_bolo": {
            "plate": "BLC-4491",
            "make": "Pegassi",
            "model": "Infernus",
            "primary_color": "Red"
        },
        "warrant_found": True,
        "trevor_warrant_found": True,
        "warrant": {
            "name_id": 3,
            "warrant_name": "Evading Police Officer - Felony"
        },
        "citation_found": True,
        "trevor_citation_found": False,
        "citation": {
            "name_id": 99,
            "citation_name": "Reckless Driving",
            "fine": 750.00
        }
    }
    results.append(run_test(
        "multi_jurisdiction_pursuit: wrong-target citation (name_id=99 instead of Trevor=3)",
        verify_multi_jurisdiction_pursuit, wrong_target_mjp_citation, task_info_mjp,
        expected_pass=False, expected_score_range=(60, 68),
        description="Call(15) + BOLO(20) + Warrant correct(30) + Citation zeroed(0) = 65 pts. Passed=False."
    ))

    # Partial completion test: call + vehicle BOLO only
    partial_mjp = {
        "call_found": True,
        "call": {
            "type": "10-80 Pursuit",
            "street1": "Del Perro Boulevard",
            "narrative": "Vehicle pursuit near Del Perro Blvd"
        },
        "vehicle_bolo_found": True,
        "vehicle_bolo": {
            "plate": "BLC-4491",
            "make": "Pegassi",
            "model": "Infernus",
            "primary_color": "Red"
        },
        "warrant_found": False,
        "trevor_warrant_found": False,
        "warrant": {},
        "citation_found": False,
        "trevor_citation_found": False,
        "citation": {}
    }
    results.append(run_test(
        "multi_jurisdiction_pursuit: partial (call + vehicle BOLO only)",
        verify_multi_jurisdiction_pursuit, partial_mjp, task_info_mjp,
        expected_pass=False, expected_score_range=(33, 37),
        description="Call(15) + Vehicle BOLO(20) = 35 pts. Passed=False."
    ))

    # =========================================================================
    # Summary
    # =========================================================================
    print("\n" + "=" * 60)
    passed_count = sum(1 for r in results if r['status'] == 'PASS')
    failed_count = sum(1 for r in results if r['status'] == 'FAIL')
    print(f"VALIDATION TEST SUMMARY: {passed_count}/{len(results)} passed")
    if failed_count > 0:
        print(f"FAILED TESTS:")
        for r in results:
            if r['status'] == 'FAIL':
                print(f"  - {r['test_name']}")
                print(f"    expected score {r['expected_score_range']}, got {r['actual_score']}")
                print(f"    feedback: {r['feedback']}")

    # Save evidence
    evidence = {
        "test_type": "phase5_validation",
        "total_tests": len(results),
        "passed": passed_count,
        "failed": failed_count,
        "all_pass": failed_count == 0,
        "tests": results
    }

    evidence_path = os.path.join(os.path.dirname(__file__), 'validation_test_results.json')
    with open(evidence_path, 'w') as f:
        json.dump(evidence, f, indent=2)
    print(f"\nResults saved to {evidence_path}")

    return 0 if failed_count == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
