#!/usr/bin/env python3
"""
Offline pipeline tests for freecad_envb new tasks.

Tests do-nothing scenario (score=0, passed=False) for all 5 new tasks
without requiring a live VM — uses mock copy_from_env that raises FileNotFoundError.

Usage:
    cd /path/to/Gym-Anything_for_cmu_super_clean
    python benchmarks/environments/freecad_envb/dev/test_new_tasks_pipeline.py
"""

import sys
import os

# Add repo root to path so we can import verifiers directly
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, REPO_ROOT)

from examples.freecad_envb.tasks.parametric_motor_mount.verifier import verify_parametric_motor_mount
from examples.freecad_envb.tasks.robot_arm_link_drawings.verifier import verify_robot_arm_link_drawings
from examples.freecad_envb.tasks.eia_rack_panel_design.verifier import verify_eia_rack_panel_design
from examples.freecad_envb.tasks.heatsink_fin_array_design.verifier import verify_heatsink_fin_array_design
from examples.freecad_envb.tasks.structural_gusset_plate.verifier import verify_structural_gusset_plate


def make_env_info_no_files():
    """Mock env_info where all file copies fail (do-nothing scenario)."""
    def copy_from_env(src, dst):
        raise FileNotFoundError(f"No such file in environment: {src}")
    return {'copy_from_env': copy_from_env}


def make_env_info_with_json(result_json: dict):
    """Mock env_info with a result JSON but no FCStd/export files."""
    import json
    import tempfile

    def copy_from_env(src, dst):
        if src.endswith('.json'):
            with open(dst, 'w') as f:
                json.dump(result_json, f)
        else:
            raise FileNotFoundError(f"No such file in environment: {src}")
    return {'copy_from_env': copy_from_env}


VERIFIERS = [
    ("parametric_motor_mount",    verify_parametric_motor_mount),
    ("robot_arm_link_drawings",   verify_robot_arm_link_drawings),
    ("eia_rack_panel_design",     verify_eia_rack_panel_design),
    ("heatsink_fin_array_design", verify_heatsink_fin_array_design),
    ("structural_gusset_plate",   verify_structural_gusset_plate),
]


def test_do_nothing_no_files():
    """All verifiers must return score=0, passed=False when no files exist."""
    print("\n=== Test: do-nothing (no files at all) ===")
    env_info = make_env_info_no_files()
    all_passed = True
    for name, fn in VERIFIERS:
        result = fn([], env_info, {})
        ok = (result['score'] == 0 and result['passed'] is False)
        status = "PASS" if ok else "FAIL"
        print(f"  [{status}] {name}: score={result['score']}, passed={result['passed']}, feedback={result['feedback'][:80]}")
        if not ok:
            all_passed = False
    return all_passed


def test_do_nothing_with_stale_json():
    """All verifiers must return score=0 / passed=False when result JSON exists
    but FCStd is absent (fcstd_exists=False, mtime=0)."""
    print("\n=== Test: do-nothing (result JSON present, no FCStd, no exports) ===")
    result_json = {
        "task_start": 1700000000,
        "fcstd_exists": False,
        "fcstd_mtime": 0,
        "fcstd_size": 0,
        "stl_exists": False,
        "stl_size": 0,
        "step_exists": False,
        "step_size": 0,
        "pdf_exists": False,
        "pdf_size": 0,
    }
    env_info = make_env_info_with_json(result_json)
    all_passed = True
    for name, fn in VERIFIERS:
        result = fn([], env_info, {})
        ok = (result['score'] == 0 and result['passed'] is False)
        status = "PASS" if ok else "FAIL"
        print(f"  [{status}] {name}: score={result['score']}, passed={result['passed']}, feedback={result['feedback'][:80]}")
        if not ok:
            all_passed = False
    return all_passed


def test_partial_score_stl_only():
    """parametric_motor_mount: STL present but no FCStd => 25 pts (not passing)."""
    print("\n=== Test: partial — STL present, no FCStd (parametric_motor_mount) ===")
    import json

    def copy_from_env(src, dst):
        if src.endswith('.json'):
            with open(dst, 'w') as f:
                json.dump({
                    "task_start": 1700000000,
                    "fcstd_exists": False,
                    "fcstd_mtime": 0,
                    "fcstd_size": 0,
                    "stl_exists": True,
                    "stl_size": 15000,
                    "step_exists": False,
                    "step_size": 0,
                }, f)
        else:
            raise FileNotFoundError(src)

    env_info = {'copy_from_env': copy_from_env}
    result = verify_parametric_motor_mount([], env_info, {})
    ok = (result['score'] == 25 and result['passed'] is False)
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] parametric_motor_mount (STL only): score={result['score']} (expected 25), passed={result['passed']} (expected False)")
    return ok


def test_partial_score_step_only():
    """structural_gusset_plate: STEP > 5KB but no FCStd => 15 pts (not passing)."""
    print("\n=== Test: partial — STEP present, no FCStd (structural_gusset_plate) ===")
    import json

    def copy_from_env(src, dst):
        if src.endswith('.json'):
            with open(dst, 'w') as f:
                json.dump({
                    "task_start": 1700000000,
                    "fcstd_exists": False,
                    "fcstd_mtime": 0,
                    "fcstd_size": 0,
                    "step_exists": True,
                    "step_size": 9000,
                }, f)
        else:
            raise FileNotFoundError(src)

    env_info = {'copy_from_env': copy_from_env}
    result = verify_structural_gusset_plate([], env_info, {})
    ok = (result['score'] == 15 and result['passed'] is False)
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] structural_gusset_plate (STEP only): score={result['score']} (expected 15), passed={result['passed']} (expected False)")
    return ok


def make_minimal_fcstd(obj_types: list, aliases: list = None) -> bytes:
    """Build a minimal valid FCStd ZIP containing Document.xml with given PartDesign object types.

    obj_types: list of type strings, e.g. ['PartDesign::Body', 'PartDesign::Pad']
    aliases:   list of alias name strings for Spreadsheet cells (requires 'Spreadsheet::Sheet' in obj_types)
    Returns bytes of a valid ZIP file.
    """
    import io
    import zipfile as zf

    objects_xml = "\n".join(
        f'    <Object type="{t}" name="{t.split("::")[-1]}{i}"/>'
        for i, t in enumerate(obj_types)
    )

    cells_xml = ""
    if aliases and 'Spreadsheet::Sheet' in obj_types:
        cell_rows = "\n".join(
            f'          <Cell alias="{a}" address="A{i+1}" content="10"/>'
            for i, a in enumerate(aliases)
        )
        cells_xml = f"""
  <ObjectData>
    <Object name="Spreadsheet0">
      <Properties>
        <Property name="cells">
          <Cells>
{cell_rows}
          </Cells>
        </Property>
      </Properties>
    </Object>
  </ObjectData>"""

    doc_xml = f"""<?xml version='1.0' encoding='utf-8'?>
<Document>
  <Objects>
{objects_xml}
  </Objects>{cells_xml}
</Document>
"""
    buf = io.BytesIO()
    with zf.ZipFile(buf, 'w') as z:
        z.writestr('Document.xml', doc_xml)
        z.writestr('GuiDocument.xml', '<GuiDocument/>')
    return buf.getvalue()


def make_env_info_with_fcstd(json_data: dict, fcstd_bytes: bytes = None):
    """Mock env_info: copy_from_env serves JSON for .json paths, FCStd bytes for .FCStd paths."""
    import json as _json
    import shutil

    def copy_from_env(src, dst):
        if src.endswith('.json'):
            with open(dst, 'w') as f:
                _json.dump(json_data, f)
        elif src.endswith('.FCStd') and fcstd_bytes is not None:
            with open(dst, 'wb') as f:
                f.write(fcstd_bytes)
        else:
            raise FileNotFoundError(src)

    return {'copy_from_env': copy_from_env}


# ---- Phase 5: Partial completion tests ----

def test_partial_motor_mount_body_pad_no_holes():
    """parametric_motor_mount: Body+Pad but no holes, no spreadsheet → ~30 pts, passed=False."""
    print("\n=== Test: partial — Body+Pad, no holes, no spreadsheet (parametric_motor_mount) ===")
    task_start = 1700000000
    fcstd_bytes = make_minimal_fcstd(['PartDesign::Body', 'PartDesign::Pad'])
    json_data = {
        "task_start": task_start,
        "fcstd_exists": True,
        "fcstd_mtime": task_start + 60,
        "fcstd_size": len(fcstd_bytes),
        "stl_exists": False,
        "stl_size": 0,
    }
    env_info = make_env_info_with_fcstd(json_data, fcstd_bytes)
    result = verify_parametric_motor_mount([], env_info, {})
    # Expected: 10 (exists) + 10 (modified) + 5 (body) + 5 (pad) = 30
    ok = (20 <= result['score'] <= 40 and result['passed'] is False)
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] score={result['score']} (expected 20-40), passed={result['passed']} (expected False)")
    print(f"  feedback: {result['feedback'][:100]}")
    return ok


def test_partial_motor_mount_with_spreadsheet_and_4holes():
    """parametric_motor_mount: Spreadsheet(3 aliases)+Body+Pad+4 holes → ~75 pts, passed=True."""
    print("\n=== Test: partial — Spreadsheet+Body+Pad+4holes (parametric_motor_mount) ===")
    task_start = 1700000000
    fcstd_bytes = make_minimal_fcstd(
        ['Spreadsheet::Sheet', 'PartDesign::Body', 'PartDesign::Pad',
         'PartDesign::Hole', 'PartDesign::Hole', 'PartDesign::Hole', 'PartDesign::Hole'],
        aliases=['motor_pitch', 'bore_dia', 'base_t']
    )
    json_data = {
        "task_start": task_start,
        "fcstd_exists": True,
        "fcstd_mtime": task_start + 60,
        "fcstd_size": len(fcstd_bytes),
        "stl_exists": False,
        "stl_size": 0,
    }
    env_info = make_env_info_with_fcstd(json_data, fcstd_bytes)
    result = verify_parametric_motor_mount([], env_info, {})
    # Expected: 10+10+15+10+5+5+20 = 75 pts → passed=True (but no STL)
    ok = (65 <= result['score'] <= 85)
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] score={result['score']} (expected 65-85), passed={result['passed']}")
    print(f"  feedback: {result['feedback'][:100]}")
    return ok


def test_partial_drawings_drawpage_no_dims():
    """robot_arm_link_drawings: DrawPage+2 views, no dimensions → partial, not passing."""
    print("\n=== Test: partial — DrawPage+2views, no dims (robot_arm_link_drawings) ===")
    task_start = 1700000000
    fcstd_bytes = make_minimal_fcstd([
        'TechDraw::DrawPage',
        'TechDraw::DrawViewPart',
        'TechDraw::DrawViewPart',
    ])
    json_data = {
        "task_start": task_start,
        "fcstd_exists": True,
        "fcstd_mtime": task_start + 60,
        "fcstd_size": len(fcstd_bytes),
        "pdf_exists": False,
        "pdf_size": 0,
    }
    env_info = make_env_info_with_fcstd(json_data, fcstd_bytes)
    result = verify_robot_arm_link_drawings([], env_info, {})
    # Expected: 10+10+20+15 = 55 pts → passed=False (need 70)
    ok = (40 <= result['score'] <= 65 and result['passed'] is False)
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] score={result['score']} (expected 40-65), passed={result['passed']} (expected False)")
    print(f"  feedback: {result['feedback'][:100]}")
    return ok


def test_partial_rack_panel_body_no_cutouts():
    """eia_rack_panel_design: Spreadsheet+Body+Pad but no cutouts → partial, not passing."""
    print("\n=== Test: partial — Spreadsheet+Body+Pad, no cutouts (eia_rack_panel_design) ===")
    task_start = 1700000000
    fcstd_bytes = make_minimal_fcstd(
        ['Spreadsheet::Sheet', 'PartDesign::Body', 'PartDesign::Pad'],
        aliases=['panel_height', 'panel_width', 'hole_dia']
    )
    json_data = {
        "task_start": task_start,
        "fcstd_exists": True,
        "fcstd_mtime": task_start + 60,
        "fcstd_size": len(fcstd_bytes),
        "step_exists": False,
        "step_size": 0,
    }
    env_info = make_env_info_with_fcstd(json_data, fcstd_bytes)
    result = verify_eia_rack_panel_design([], env_info, {})
    # Expected: 10+10+20+10 = 50 pts → passed=False (need 70)
    ok = (35 <= result['score'] <= 55 and result['passed'] is False)
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] score={result['score']} (expected 35-55), passed={result['passed']} (expected False)")
    print(f"  feedback: {result['feedback'][:100]}")
    return ok


def test_partial_heatsink_no_pattern():
    """heatsink_fin_array_design: Spreadsheet+Body+Pad+mount holes but no LinearPattern → partial, not passing."""
    print("\n=== Test: partial — Spreadsheet+Body+Pad+holes, no LinearPattern (heatsink_fin_array_design) ===")
    task_start = 1700000000
    fcstd_bytes = make_minimal_fcstd(
        ['Spreadsheet::Sheet', 'PartDesign::Body', 'PartDesign::Pad',
         'PartDesign::Hole', 'PartDesign::Hole'],
        aliases=['fin_count', 'fin_thickness', 'fin_height', 'base_height']
    )
    json_data = {
        "task_start": task_start,
        "fcstd_exists": True,
        "fcstd_mtime": task_start + 60,
        "fcstd_size": len(fcstd_bytes),
        "stl_exists": False,
        "stl_size": 0,
        "step_exists": False,
        "step_size": 0,
    }
    env_info = make_env_info_with_fcstd(json_data, fcstd_bytes)
    result = verify_heatsink_fin_array_design([], env_info, {})
    # Expected: 10+10+20+10+10 = 60 pts → passed=False (need 70)
    ok = (45 <= result['score'] <= 65 and result['passed'] is False)
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] score={result['score']} (expected 45-65), passed={result['passed']} (expected False)")
    print(f"  feedback: {result['feedback'][:100]}")
    return ok


def test_partial_gusset_few_holes():
    """structural_gusset_plate: Spreadsheet+Body+Pad+3 holes (< 6) → partial, not passing."""
    print("\n=== Test: partial — Spreadsheet+Body+Pad+3holes (structural_gusset_plate) ===")
    task_start = 1700000000
    fcstd_bytes = make_minimal_fcstd(
        ['Spreadsheet::Sheet', 'PartDesign::Body', 'PartDesign::Pad',
         'PartDesign::Hole', 'PartDesign::Hole', 'PartDesign::Hole'],
        aliases=['bolt_gauge', 'bolt_pitch']
    )
    json_data = {
        "task_start": task_start,
        "fcstd_exists": True,
        "fcstd_mtime": task_start + 60,
        "fcstd_size": len(fcstd_bytes),
        "step_exists": False,
        "step_size": 0,
    }
    env_info = make_env_info_with_fcstd(json_data, fcstd_bytes)
    result = verify_structural_gusset_plate([], env_info, {})
    # Expected: 10+10+15+10+5+18 = ~68 pts → passed=False (need 70; 3 holes gives partial 18 pts)
    ok = (40 <= result['score'] <= 68 and result['passed'] is False)
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] score={result['score']} (expected 40-68), passed={result['passed']} (expected False)")
    print(f"  feedback: {result['feedback'][:100]}")
    return ok


def main():
    results = []
    results.append(test_do_nothing_no_files())
    results.append(test_do_nothing_with_stale_json())
    results.append(test_partial_score_stl_only())
    results.append(test_partial_score_step_only())

    print("\n--- Phase 5: Partial Completion Tests ---")
    results.append(test_partial_motor_mount_body_pad_no_holes())
    results.append(test_partial_motor_mount_with_spreadsheet_and_4holes())
    results.append(test_partial_drawings_drawpage_no_dims())
    results.append(test_partial_rack_panel_body_no_cutouts())
    results.append(test_partial_heatsink_no_pattern())
    results.append(test_partial_gusset_few_holes())

    total = len(results)
    passed = sum(results)
    print(f"\n{'='*50}")
    print(f"Results: {passed}/{total} test groups passed")
    if passed == total:
        print("ALL TESTS PASSED")
        sys.exit(0)
    else:
        print("SOME TESTS FAILED")
        sys.exit(1)


if __name__ == '__main__':
    main()
