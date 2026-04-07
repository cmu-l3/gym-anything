#!/usr/bin/env python3
"""Verifier for onboard_new_operator_fleet task.

Checks the full operator onboarding workflow:
  1. Company 'Horizon Aerial Services Pvt Ltd' created correctly
  2. Operator linked to company with M2M activities/authorizations
  3. Two Person records (Arjun Mehta, Priya Sharma)
  4. Two Pilot records linked to the Horizon Aerial operator
  5. Two Aircraft (HA-Scout-01, HA-Scout-02) with correct operator
  6. FlightPlan 'Mumbai Harbor Survey' with GeoJSON
  7. FlightOperation 'HA Fleet Certification Flight' with correct links

Scoring (100 points total):
  - Company exists with correct name:                8 pts
  - Company role=Operator, country=India:            7 pts
  - Operator linked to company exists:              10 pts
  - Operator has photographing + videotaping:        5 pts
  - Operator has SORA authorization:                 5 pts
  - Person Arjun Mehta exists:                       5 pts
  - Person Priya Sharma exists:                      5 pts
  - Pilot for Arjun -> Horizon Aerial:               8 pts
  - Pilot for Priya -> Horizon Aerial:               7 pts
  - Aircraft HA-Scout-01 with correct operator:     10 pts
  - Aircraft HA-Scout-02 with correct operator:     10 pts
  - FlightPlan with GeoJSON:                        10 pts
  - FlightOperation exists:                          5 pts
  - FlightOperation correct links:                   5 pts

Pass threshold: 60 points

NOTE: VLM checklist verification is used as the primary evaluator.
This programmatic verifier provides a complementary check.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

EXPECTED_COMPANY = "Horizon Aerial Services Pvt Ltd"
EXPECTED_OPERATOR_COMPANY = "Horizon Aerial Services Pvt Ltd"


def verify_onboard_new_operator_fleet(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_path = tmp.name
    tmp.close()
    try:
        copy_from_env(
            "/tmp/onboard_new_operator_fleet_result.json", tmp_path
        )
        with open(tmp_path) as f:
            data = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    if data.get("error"):
        return {"passed": False, "score": 0,
                "feedback": f"Export error: {data['error']}"}

    score = 0
    fb = []  # feedback parts

    comp = data.get("company")
    op = data.get("operator")
    persons = data.get("persons", [])
    pilots = data.get("pilots", [])
    aircraft_list = data.get("aircraft", [])
    fp = data.get("flight_plan")
    fo = data.get("flight_operation")

    # ── 1. Company exists (8 pts) ────────────────────────────────────────────
    if comp and comp.get("full_name", "").strip() == EXPECTED_COMPANY:
        score += 8
        fb.append(f"Company '{EXPECTED_COMPANY}' created (+8)")
    elif comp:
        score += 4
        fb.append(f"Company found: '{comp.get('full_name')}' (+4)")
    else:
        fb.append(f"Company '{EXPECTED_COMPANY}' not found")

    # ── 2. Company role + country (7 pts) ────────────────────────────────────
    if comp:
        role_ok = comp.get("role") == 2
        country_raw = str(comp.get("country", "")).strip().upper()
        country_ok = country_raw in ("IN", "INDIA")
        if role_ok and country_ok:
            score += 7
            fb.append("Company role=Operator, country=India (+7)")
        elif role_ok or country_ok:
            score += 3
            fb.append(f"Company role={comp.get('role')}, "
                      f"country={country_raw} (+3)")
        else:
            fb.append(f"Company role={comp.get('role')}, "
                      f"country={country_raw}")

    # ── 3. Operator linked to company (10 pts) ──────────────────────────────
    if op and (op.get("company_full_name", "").strip()
               == EXPECTED_COMPANY):
        score += 10
        fb.append("Operator linked to Horizon Aerial (+10)")
    elif op:
        score += 5
        fb.append(f"Operator found but company: "
                  f"'{op.get('company_full_name')}' (+5)")
    else:
        fb.append("Operator not found")

    # ── 4. Operator M2M activities (5 pts) ──────────────────────────────────
    if op:
        acts = set(op.get("authorized_activities", []))
        if "photographing" in acts and "videotaping" in acts:
            score += 5
            fb.append("Both activities assigned (+5)")
        elif acts:
            score += 2
            fb.append(f"Partial activities: {acts} (+2)")
        else:
            fb.append("No activities assigned")

    # ── 5. Operator M2M authorizations (5 pts) ──────────────────────────────
    if op:
        auths = set(op.get("operational_authorizations", []))
        if "SORA" in auths or "SORA V2" in auths:
            score += 5
            fb.append("SORA authorization assigned (+5)")
        elif auths:
            score += 2
            fb.append(f"Partial authorizations: {auths} (+2)")
        else:
            fb.append("No authorizations assigned")

    # ── 6. Person Arjun Mehta (5 pts) ───────────────────────────────────────
    arjun = next(
        (p for p in persons
         if "arjun" in p.get("first_name", "").lower()),
        None
    )
    if arjun:
        score += 5
        fb.append(f"Person Arjun Mehta found (+5)")
    else:
        fb.append("Person Arjun Mehta not found")

    # ── 7. Person Priya Sharma (5 pts) ──────────────────────────────────────
    priya = next(
        (p for p in persons
         if "priya" in p.get("first_name", "").lower()),
        None
    )
    if priya:
        score += 5
        fb.append(f"Person Priya Sharma found (+5)")
    else:
        fb.append("Person Priya Sharma not found")

    # ── 8. Pilot for Arjun -> Horizon Aerial (8 pts) ────────────────────────
    arjun_pilot = next(
        (p for p in pilots
         if "arjun" in p.get("person_name", "").lower()),
        None
    )
    if arjun_pilot:
        if arjun_pilot.get("operator_company") == EXPECTED_COMPANY:
            score += 8
            fb.append("Pilot Arjun -> Horizon Aerial (+8)")
        else:
            score += 4
            fb.append(f"Pilot Arjun found but operator: "
                      f"'{arjun_pilot.get('operator_company')}' (+4)")
    else:
        fb.append("Pilot for Arjun Mehta not found")

    # ── 9. Pilot for Priya -> Horizon Aerial (7 pts) ────────────────────────
    priya_pilot = next(
        (p for p in pilots
         if "priya" in p.get("person_name", "").lower()),
        None
    )
    if priya_pilot:
        if priya_pilot.get("operator_company") == EXPECTED_COMPANY:
            score += 7
            fb.append("Pilot Priya -> Horizon Aerial (+7)")
        else:
            score += 3
            fb.append(f"Pilot Priya found but operator: "
                      f"'{priya_pilot.get('operator_company')}' (+3)")
    else:
        fb.append("Pilot for Priya Sharma not found")

    # ── 10. Aircraft HA-Scout-01 (10 pts) ────────────────────────────────────
    ac1 = next(
        (a for a in aircraft_list if a.get("name") == "HA-Scout-01"),
        None
    )
    if ac1:
        if ac1.get("operator_company") == EXPECTED_COMPANY:
            score += 10
            fb.append("Aircraft HA-Scout-01 correct operator (+10)")
        else:
            score += 5
            fb.append(f"Aircraft HA-Scout-01 found, operator: "
                      f"'{ac1.get('operator_company')}' (+5)")
    else:
        fb.append("Aircraft HA-Scout-01 not found")

    # ── 11. Aircraft HA-Scout-02 (10 pts) ────────────────────────────────────
    ac2 = next(
        (a for a in aircraft_list if a.get("name") == "HA-Scout-02"),
        None
    )
    if ac2:
        if ac2.get("operator_company") == EXPECTED_COMPANY:
            score += 10
            fb.append("Aircraft HA-Scout-02 correct operator (+10)")
        else:
            score += 5
            fb.append(f"Aircraft HA-Scout-02 found, operator: "
                      f"'{ac2.get('operator_company')}' (+5)")
    else:
        fb.append("Aircraft HA-Scout-02 not found")

    # ── 12. FlightPlan with GeoJSON (10 pts) ────────────────────────────────
    if fp and fp.get("name", "").strip() == "Mumbai Harbor Survey":
        geo_str = fp.get("geo_json", "")
        geo_valid = False
        if geo_str and len(str(geo_str)) > 10:
            try:
                geo_obj = (json.loads(geo_str)
                           if isinstance(geo_str, str) else geo_str)
                if isinstance(geo_obj, dict) and "type" in geo_obj:
                    geo_valid = True
            except Exception:
                pass
        if geo_valid:
            score += 10
            fb.append("FlightPlan 'Mumbai Harbor Survey' with "
                      "valid GeoJSON (+10)")
        else:
            score += 5
            fb.append("FlightPlan found but GeoJSON invalid (+5)")
    elif fp:
        score += 3
        fb.append(f"FlightPlan found: '{fp.get('name')}' (+3)")
    else:
        fb.append("FlightPlan 'Mumbai Harbor Survey' not found")

    # ── 13. FlightOperation exists (5 pts) ──────────────────────────────────
    if fo and fo.get("name", "").strip() == "HA Fleet Certification Flight":
        score += 5
        fb.append("FlightOperation 'HA Fleet Certification Flight' "
                  "created (+5)")
    elif fo:
        score += 2
        fb.append(f"FlightOperation found: '{fo.get('name')}' (+2)")
    else:
        fb.append("FlightOperation 'HA Fleet Certification Flight' "
                  "not found")

    # ── 14. FlightOperation correct links (5 pts) ───────────────────────────
    if fo:
        links_ok = 0
        if fo.get("drone_name") == "HA-Scout-01":
            links_ok += 1
        if fo.get("flight_plan_name") == "Mumbai Harbor Survey":
            links_ok += 1
        if fo.get("pilot_name") and "arjun" in fo["pilot_name"].lower():
            links_ok += 1
        if links_ok >= 2:
            score += 5
            fb.append(f"FlightOperation links correct "
                      f"({links_ok}/3 matched) (+5)")
        elif links_ok >= 1:
            score += 2
            fb.append(f"FlightOperation partial links "
                      f"({links_ok}/3 matched) (+2)")
        else:
            fb.append("FlightOperation links incorrect")

    passed = score >= 60
    feedback = "\n".join(fb)
    feedback += (f"\n\nTotal score: {score}/100 "
                 f"({'PASSED' if passed else 'FAILED'}, threshold 60)")

    return {"passed": passed, "score": score, "feedback": feedback}
