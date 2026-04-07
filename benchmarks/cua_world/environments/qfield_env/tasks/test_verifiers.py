#!/usr/bin/env python3
"""
Offline unit tests for all 5 new QField hard-task verifiers.
Tests do-nothing, partial, and full-completion scenarios without a live VM.

Strategy: mock copy_from_env to serve the ORIGINAL (unmodified) GeoPackage
for do-nothing tests, and a MODIFIED copy for completion tests.
"""

import importlib.util
import sqlite3
import shutil
import tempfile
import os
import sys

DATA_DIR = os.path.join(os.path.dirname(__file__), '..', 'data')
TASKS_DIR = os.path.dirname(__file__)


def load_verifier(task_name, func_name):
    path = os.path.join(TASKS_DIR, task_name, 'verifier.py')
    spec = importlib.util.spec_from_file_location('verifier', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, func_name)


def make_env(gpkg_path):
    """Return env_info with copy_from_env pointing to a specific gpkg file."""
    def copy_from_env(src, dst):
        if not os.path.exists(gpkg_path):
            raise FileNotFoundError(f"Source not found: {gpkg_path}")
        shutil.copy2(gpkg_path, dst)
    return {'copy_from_env': copy_from_env}


def make_env_missing():
    def copy_from_env(src, dst):
        raise FileNotFoundError(f"Simulated: no file at {src}")
    return {'copy_from_env': copy_from_env}


def make_task_info(gpkg_name):
    return {
        'metadata': {
            'result_file': f'/sdcard/Android/data/ch.opengis.qfield/files/{gpkg_name}'
        }
    }


# -------------------------------------------------------------------------
# Test 1: wildlife_species_audit
# -------------------------------------------------------------------------

def test_wildlife():
    print("\n--- wildlife_species_audit verifier ---")
    verify = load_verifier('wildlife_species_audit', 'check_wildlife_species_audit')
    orig_gpkg = os.path.join(DATA_DIR, 'wildlife_species_audit.gpkg')
    task_info = make_task_info('wildlife_species_audit.gpkg')

    # Do-nothing test (missing file)
    r = verify([], make_env_missing(), task_info)
    assert r['passed'] is False and r['score'] == 0, f"Missing file: {r}"
    print("  PASS: missing file → score=0, passed=False")

    # Do-nothing test (unmodified DB — all wrong statuses still wrong)
    r = verify([], make_env(orig_gpkg), task_info)
    assert r['passed'] is False, f"Do-nothing should not pass: {r}"
    print(f"  PASS: do-nothing → score={r['score']}, passed=False")

    # Full completion: create modified copy with all 4 statuses corrected + notes
    tmp = tempfile.mktemp(suffix='.gpkg')
    shutil.copy2(orig_gpkg, tmp)
    conn = sqlite3.connect(tmp)
    corrections = {
        'Grus americana': ('EN', 'Endangered: <230 adults remain in wild, USFWS recovery plan active'),
        'Bubo scandiacus': ('VU', 'Vulnerable: breeding population declining due to lemming cycle disruption'),
        'Charadrius melodus': ('NT', 'Near Threatened: Great Plains population recovering but Atlantic coast declining'),
        'Limosa fedoa': ('NT', 'Near Threatened: breeding habitat loss in prairie pothole region'),
    }
    for sp, (status, note) in corrections.items():
        conn.execute(
            "UPDATE species_observations SET conservation_status=?, priority_note=? "
            "WHERE species_name=?",
            (status, note, sp)
        )
    conn.commit()
    conn.close()

    r = verify([], make_env(tmp), task_info)
    os.unlink(tmp)
    assert r['passed'] is True and r['score'] >= 60, f"Full completion failed: {r}"
    print(f"  PASS: full completion → score={r['score']}, passed=True")

    # Partial: only 2 statuses corrected
    tmp2 = tempfile.mktemp(suffix='.gpkg')
    shutil.copy2(orig_gpkg, tmp2)
    conn = sqlite3.connect(tmp2)
    for sp, (status, note) in list(corrections.items())[:2]:
        conn.execute(
            "UPDATE species_observations SET conservation_status=?, priority_note=? "
            "WHERE species_name=?",
            (status, note, sp)
        )
    conn.commit()
    conn.close()
    r = verify([], make_env(tmp2), task_info)
    os.unlink(tmp2)
    assert r['passed'] is False, f"Partial should not pass: {r}"
    print(f"  PASS: partial (2/4 corrected) → score={r['score']}, passed=False")
    print("  wildlife_species_audit: ALL TESTS PASSED")


# -------------------------------------------------------------------------
# Test 2: water_station_triage
# -------------------------------------------------------------------------

def test_water():
    print("\n--- water_station_triage verifier ---")
    verify = load_verifier('water_station_triage', 'check_water_station_triage')
    orig_gpkg = os.path.join(DATA_DIR, 'water_station_triage.gpkg')
    task_info = make_task_info('water_station_triage.gpkg')

    # Do-nothing
    r = verify([], make_env_missing(), task_info)
    assert r['passed'] is False and r['score'] == 0, f"Missing file: {r}"
    print("  PASS: missing file → score=0, passed=False")

    r = verify([], make_env(orig_gpkg), task_info)
    assert r['passed'] is False, f"Do-nothing should not pass: {r}"
    print(f"  PASS: do-nothing → score={r['score']}, passed=False")

    # Full completion: mark all anomalous stations ACTION_REQUIRED
    tmp = tempfile.mktemp(suffix='.gpkg')
    shutil.copy2(orig_gpkg, tmp)
    conn = sqlite3.connect(tmp)
    conn.row_factory = sqlite3.Row

    rows = conn.execute(
        "SELECT fid, ph, dissolved_oxygen_mgl, turbidity_ntu, nitrate_mgl "
        "FROM monitoring_stations"
    ).fetchall()

    for row in rows:
        ph = row['ph']; do_ = row['dissolved_oxygen_mgl']
        turb = row['turbidity_ntu']; nit = row['nitrate_mgl']
        is_anom = (
            (ph is not None and (ph < 6.5 or ph > 8.5)) or
            (do_ is not None and (do_ < 6.0 or do_ > 12.0)) or
            (turb is not None and turb > 100.0) or
            (nit is not None and nit > 10.0)
        )
        if is_anom:
            conn.execute(
                "UPDATE monitoring_stations SET triage_status='ACTION_REQUIRED', "
                "inspector_note='Out-of-range parameter detected per EPA freshwater standards' "
                "WHERE fid=?", (row['fid'],)
            )
    conn.commit()
    conn.close()

    r = verify([], make_env(tmp), task_info)
    os.unlink(tmp)
    assert r['passed'] is True and r['score'] >= 60, f"Full completion failed: {r}"
    print(f"  PASS: full completion → score={r['score']}, passed=True")
    print("  water_station_triage: ALL TESTS PASSED")


# -------------------------------------------------------------------------
# Test 3: utility_pole_inspection
# -------------------------------------------------------------------------

def test_poles():
    print("\n--- utility_pole_inspection verifier ---")
    verify = load_verifier('utility_pole_inspection', 'check_utility_pole_inspection')
    orig_gpkg = os.path.join(DATA_DIR, 'utility_pole_inspection.gpkg')
    task_info = make_task_info('utility_pole_inspection.gpkg')

    r = verify([], make_env_missing(), task_info)
    assert r['passed'] is False and r['score'] == 0, f"Missing file: {r}"
    print("  PASS: missing file → score=0, passed=False")

    r = verify([], make_env(orig_gpkg), task_info)
    assert r['passed'] is False, f"Do-nothing should not pass: {r}"
    print(f"  PASS: do-nothing → score={r['score']}, passed=False")

    # Full completion
    tmp = tempfile.mktemp(suffix='.gpkg')
    shutil.copy2(orig_gpkg, tmp)
    conn = sqlite3.connect(tmp)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        "SELECT fid, material, install_year, condition_rating FROM pole_inventory"
    ).fetchall()
    for row in rows:
        mat = (row['material'] or '').strip()
        try:
            yr = int(row['install_year'] or 9999)
        except (ValueError, TypeError):
            yr = 9999
        cond = (row['condition_rating'] or '').strip()
        if mat == 'Wood' and yr < 2010 and cond in ('Fair', 'Poor', 'Critical'):
            conn.execute(
                "UPDATE pole_inventory SET replacement_flag='SCHEDULE', "
                "work_order_notes='Wood pole pre-2010 with degraded condition rating' "
                "WHERE fid=?", (row['fid'],)
            )
    conn.commit()
    conn.close()

    r = verify([], make_env(tmp), task_info)
    os.unlink(tmp)
    assert r['passed'] is True and r['score'] >= 60, f"Full completion failed: {r}"
    print(f"  PASS: full completion → score={r['score']}, passed=True")
    print("  utility_pole_inspection: ALL TESTS PASSED")


# -------------------------------------------------------------------------
# Test 4: crop_pest_scouting
# -------------------------------------------------------------------------

def test_crops():
    print("\n--- crop_pest_scouting verifier ---")
    verify = load_verifier('crop_pest_scouting', 'check_crop_pest_scouting')
    orig_gpkg = os.path.join(DATA_DIR, 'crop_pest_scouting.gpkg')
    task_info = make_task_info('crop_pest_scouting.gpkg')

    r = verify([], make_env_missing(), task_info)
    assert r['passed'] is False and r['score'] == 0, f"Missing file: {r}"
    print("  PASS: missing file → score=0, passed=False")

    r = verify([], make_env(orig_gpkg), task_info)
    assert r['passed'] is False, f"Do-nothing should not pass: {r}"
    print(f"  PASS: do-nothing → score={r['score']}, passed=False")

    # Full completion
    tmp = tempfile.mktemp(suffix='.gpkg')
    shutil.copy2(orig_gpkg, tmp)
    conn = sqlite3.connect(tmp)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        "SELECT fid, scout_date, soybean_aphid_per_plant, "
        "corn_rootworm_beetles_per_trap, corn_borer_egg_masses_per_100, "
        "bean_leaf_beetle_per_sweep, defoliation_pct FROM scout_zones"
    ).fetchall()
    from datetime import date as _date, timedelta
    for row in rows:
        exceeds = (
            (row['soybean_aphid_per_plant'] or 0) > 250 or
            (row['corn_rootworm_beetles_per_trap'] or 0) > 5 or
            (row['corn_borer_egg_masses_per_100'] or 0) > 10 or
            (row['bean_leaf_beetle_per_sweep'] or 0) > 8 or
            (row['defoliation_pct'] or 0) > 20
        )
        if exceeds:
            scout_date = row['scout_date'] or '2024-07-01'
            try:
                d = _date.fromisoformat(scout_date[:10])
                recheck = (d + timedelta(days=7)).isoformat()
            except Exception:
                recheck = '2024-07-08'
            conn.execute(
                "UPDATE scout_zones SET treatment_recommendation='TREAT', "
                "action_notes='Pest count exceeds IPM economic threshold - treatment required', "
                "recheck_date=? WHERE fid=?",
                (recheck, row['fid'])
            )
    conn.commit()
    conn.close()

    r = verify([], make_env(tmp), task_info)
    os.unlink(tmp)
    assert r['passed'] is True and r['score'] >= 60, f"Full completion failed: {r}"
    print(f"  PASS: full completion → score={r['score']}, passed=True")
    print("  crop_pest_scouting: ALL TESTS PASSED")


# -------------------------------------------------------------------------
# Test 5: forest_stand_reinventory
# -------------------------------------------------------------------------

def test_forest():
    print("\n--- forest_stand_reinventory verifier ---")
    verify = load_verifier('forest_stand_reinventory', 'check_forest_stand_reinventory')
    orig_gpkg = os.path.join(DATA_DIR, 'forest_stand_reinventory.gpkg')
    task_info = make_task_info('forest_stand_reinventory.gpkg')

    r = verify([], make_env_missing(), task_info)
    assert r['passed'] is False and r['score'] == 0, f"Missing file: {r}"
    print("  PASS: missing file → score=0, passed=False")

    r = verify([], make_env(orig_gpkg), task_info)
    assert r['passed'] is False, f"Do-nothing should not pass: {r}"
    print(f"  PASS: do-nothing → score={r['score']}, passed=False")

    # Full completion
    tmp = tempfile.mktemp(suffix='.gpkg')
    shutil.copy2(orig_gpkg, tmp)
    conn = sqlite3.connect(tmp)
    conn.row_factory = sqlite3.Row
    stands = conn.execute(
        "SELECT fid, stand_id, last_inventory_date FROM forest_stands"
    ).fetchall()

    for row in stands:
        try:
            inv_year = int(str(row['last_inventory_date'])[:4])
        except Exception:
            inv_year = 2024
        if inv_year <= 2019:
            years_overdue = 2024 - inv_year
            priority = 1 if years_overdue > 7 else 2
            notes = f"Overdue by {years_overdue} years (last: {row['last_inventory_date']})"
            conn.execute(
                "UPDATE forest_stands SET reinventory_status='OVERDUE', "
                "field_notes=?, priority_rank=? WHERE fid=?",
                (notes, priority, row['fid'])
            )
            # Add a tree measurement
            conn.execute(
                "INSERT INTO tree_measurements "
                "(stand_fid, stand_id, tree_tag, species_code, dbh_inches, "
                "total_height_ft, crown_class, condition_code, azimuth_deg, "
                "distance_ft, measured_date, crew_member) "
                "VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                (row['fid'], row['stand_id'], f"T-{row['fid']:04d}-001",
                 'POTR5', 12.5, 65.0, 'Codominant', '1', 90, 15.0,
                 '2024-07-01', 'USFS-NF-01')
            )
    conn.commit()
    conn.close()

    r = verify([], make_env(tmp), task_info)
    os.unlink(tmp)
    assert r['passed'] is True and r['score'] >= 60, f"Full completion failed: {r}"
    print(f"  PASS: full completion → score={r['score']}, passed=True")
    print("  forest_stand_reinventory: ALL TESTS PASSED")


if __name__ == '__main__':
    print("Running offline verifier unit tests for 5 new QField hard tasks...")
    errors = []
    for test_fn in [test_wildlife, test_water, test_poles, test_crops, test_forest]:
        try:
            test_fn()
        except AssertionError as e:
            print(f"  ASSERTION FAILED: {e}")
            errors.append(str(e))
        except Exception as e:
            import traceback
            print(f"  ERROR: {e}")
            traceback.print_exc()
            errors.append(str(e))

    print(f"\n{'='*50}")
    if errors:
        print(f"FAILED: {len(errors)} test(s) failed")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)
    else:
        print("ALL TESTS PASSED")
