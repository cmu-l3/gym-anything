"""
Verifier for ifc_quality_schema_remediation task.

Scoring (100 points total):
  file_new        (10 pts) : Output IFC exists and is newer than task start
  site_coords     (25 pts) : IfcSite has RefLatitude and RefLongitude set
  building_addr   (25 pts) : IfcBuilding has BuildingAddress with correct town/country
  spaces_named    (20 pts) : Partial: unique non-generic space names / total spaces * 20
  walls_named     (20 pts) : Partial: unique non-generic wall names / total walls * 20

Pass threshold: 65
Anti-pattern: Saving the contaminated file directly scores 0 (appearance_contaminated gate).
Do-nothing: file doesn't exist → score 0.
"""
import json
import os
import tempfile


def verify_quality_schema_remediation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env("/tmp/quality_remediation_result.json", tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"FAIL: Could not read result file: {e}"
        }
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    feedback = []
    score = 0

    # ── Gate: output file must exist and be new ────────────────────────────
    if not result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: Output IFC /home/ga/BIMProjects/fzk_remediated.ifc was not created."
        }

    file_mtime = float(result.get("file_mtime", 0))
    task_start = float(result.get("task_start", 0))
    if file_mtime <= task_start:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: Output IFC was not modified during the task (stale file)."
        }

    # ── Anti-gaming: reject if model still looks contaminated ─────────────
    if result.get("appears_contaminated", False):
        return {
            "passed": False,
            "score": 5,
            "feedback": "FAIL: Output model still has all contamination errors present. "
                        "The contaminated model was saved without any fixes."
        }

    score += 10
    feedback.append("PASS (+10): Output IFC file created and is new.")

    # ── Criterion 1: IfcSite geographic coordinates ───────────────────────
    site_has_coords = result.get("site_has_coordinates", False)
    site_lat = result.get("site_lat")
    site_lon = result.get("site_lon")
    if site_has_coords:
        # Validate approximate correctness (49°N, 8°E = Karlsruhe area)
        lat_ok = False
        lon_ok = False
        if site_lat and len(site_lat) >= 1 and site_lat[0] == 49:
            lat_ok = True
        if site_lon and len(site_lon) >= 1 and site_lon[0] == 8:
            lon_ok = True
        if lat_ok and lon_ok:
            score += 25
            feedback.append(f"PASS (+25): IfcSite has correct geographic coordinates (lat={site_lat}, lon={site_lon}).")
        else:
            score += 10
            feedback.append(f"PARTIAL (+10): IfcSite has coordinates but values may be incorrect (lat={site_lat}, lon={site_lon}). Expected ~49°N, 8°E.")
    else:
        feedback.append("FAIL (+0): IfcSite still has no geographic coordinates (RefLatitude/RefLongitude are NULL).")

    # ── Criterion 2: IfcBuilding postal address ───────────────────────────
    bldg_has_addr = result.get("building_has_address", False)
    bldg_town = (result.get("building_town") or "").lower()
    bldg_country = (result.get("building_country") or "").lower()
    if bldg_has_addr:
        addr_pts = 0
        addr_notes = []
        if "karlsruhe" in bldg_town:
            addr_pts += 12
            addr_notes.append("town=Karlsruhe")
        if "germany" in bldg_country or "deutschland" in bldg_country or "de" == bldg_country:
            addr_pts += 13
            addr_notes.append("country=Germany")
        if addr_pts == 0:
            addr_pts = 8
            addr_notes.append("(address present but town/country don't match spec)")
        score += addr_pts
        feedback.append(f"PASS (+{addr_pts}): IfcBuilding has BuildingAddress ({', '.join(addr_notes)}).")
    else:
        feedback.append("FAIL (+0): IfcBuilding still has no BuildingAddress.")

    # ── Criterion 3: Unique space names restored ──────────────────────────
    n_spaces = result.get("n_spaces", 0)
    unique_space_names = result.get("unique_space_names", 0)
    spaces_generic = result.get("spaces_generic", 0)
    if n_spaces > 0:
        fraction = (n_spaces - spaces_generic) / n_spaces
        space_pts = min(20, round(fraction * 20))
        score += space_pts
        if space_pts >= 18:
            feedback.append(f"PASS (+{space_pts}): All/most IfcSpace elements have unique names ({unique_space_names} unique, {spaces_generic} still generic).")
        elif space_pts > 0:
            feedback.append(f"PARTIAL (+{space_pts}): Some IfcSpace names restored ({unique_space_names} unique, {spaces_generic} still 'Room').")
        else:
            feedback.append(f"FAIL (+0): All {n_spaces} IfcSpace elements still named 'Room'.")
    else:
        feedback.append("FAIL (+0): No IfcSpace elements found in output model.")

    # ── Criterion 4: Unique wall names restored ───────────────────────────
    n_walls = result.get("n_walls", 0)
    unique_wall_names = result.get("unique_wall_names", 0)
    walls_generic = result.get("walls_generic", 0)
    if n_walls > 0:
        fraction = (n_walls - walls_generic) / n_walls
        wall_pts = min(20, round(fraction * 20))
        score += wall_pts
        if wall_pts >= 18:
            feedback.append(f"PASS (+{wall_pts}): All/most IfcWall elements have unique names ({unique_wall_names} unique, {walls_generic} still generic).")
        elif wall_pts > 0:
            feedback.append(f"PARTIAL (+{wall_pts}): Some IfcWall names restored ({unique_wall_names} unique, {walls_generic} still 'Wall').")
        else:
            feedback.append(f"FAIL (+0): All {n_walls} IfcWall elements still named 'Wall'.")
    else:
        feedback.append("FAIL (+0): No IfcWall elements found in output model.")

    PASS_THRESHOLD = 65
    passed = score >= PASS_THRESHOLD
    feedback.append(f"\nTotal score: {score}/100 (threshold: {PASS_THRESHOLD})")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
