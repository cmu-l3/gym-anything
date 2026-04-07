#!/usr/bin/env python3
"""Verifier for restore_utility_crew_field_gps task.

Pattern: Error Injection — personal sedan config with commuter routing.
Key twist: avoid_unpaved must be set to FALSE (utility crew NEEDS unpaved access
to reach pipeline valve stations and remote infrastructure). This is the opposite
of most GPS tasks where avoiding unpaved is correct.

Scoring (100 points):
  C1:  Vehicle type = VAN or TRUCK                     10 pts
  C2:  Vehicle fuel = DIESEL                             8 pts
  C3:  Vehicle speed in 100-120 km/h range               5 pts
  C4:  Route compute = Fastest '1'                       8 pts
  C5:  Avoid tolls = false (company pays)                7 pts
  C6:  Avoid unpaved = false (NEEDS access)             10 pts
  C7:  Avoid ferries = true (correct, verify kept)       4 pts
  C8:  Arrive-in-direction = true                        5 pts
  C9:  Home near Ship Channel yard                      12 pts
  C10: Work near Deer Park industrial                   12 pts
  C11: Distance = Miles                                   5 pts
  C12: Temperature = Imperial                             5 pts
  C13: Time = 12h                                         4 pts
  C14: Display extras (color/compass)                     5 pts
                                                    TOTAL: 100

Pass threshold: 55

Gates:
  - Global: wrong vehicle + wrong places + route unchanged => 0
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

# Company yard near Ship Channel: ~12000 Lawndale St
EXPECTED_HOME_LAT = 29.7250
EXPECTED_HOME_LON = -95.2600
# Deer Park industrial: ~5900 San Jacinto St
EXPECTED_WORK_LAT = 29.7000
EXPECTED_WORK_LON = -95.1240
COORD_TOLERANCE = 0.15

PASS_THRESHOLD = 55


def _coords_ok(lat, lon, elat, elon, tol):
    if lat is None or lon is None:
        return False
    try:
        return abs(float(lat) - elat) <= tol and abs(float(lon) - elon) <= tol
    except (ValueError, TypeError):
        return False


def verify_restore_utility_crew_field_gps(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(
                "/data/local/tmp/restore_utility_crew_field_gps_result.json",
                tmp.name
            )
            with open(tmp.name, 'r') as f:
                r = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        fb = []

        # === GLOBAL GATE ===
        wrong_unchanged = r.get('wrong_vehicle_unchanged', True)
        rc = str(r.get('route_compute', '')).strip()
        at = str(r.get('avoid_tolls', '')).lower()
        au = str(r.get('avoid_unpaved', '')).lower()
        home = r.get('home')
        work = r.get('work')

        # Baseline: rc=0, at=true, au=true
        route_unchanged = (rc == '0' and at == 'true' and au == 'true')

        # Home still at mall (29.7744 lat)
        home_unchanged = False
        if home is not None:
            try:
                hlat = float(home.get('latitude', 0))
                if abs(hlat - 29.7744) < 0.05:
                    home_unchanged = True
            except (ValueError, TypeError):
                pass

        if wrong_unchanged and route_unchanged and home_unchanged:
            return {"passed": False, "score": 0,
                    "feedback": "GATE: No work done — personal commuter config unchanged"}

        # C1: Vehicle type = VAN or TRUCK (10 pts)
        vtype = str(r.get('active_vehicle_type', '')).upper()
        if vtype == 'VAN':
            score += 10
            fb.append("Vehicle type VAN [+10]")
        elif vtype == 'TRUCK':
            score += 8
            fb.append("Vehicle type TRUCK — acceptable for work truck [+8]")
        else:
            fb.append(f"Vehicle type '{vtype}' — should be VAN or TRUCK [+0]")

        # C2: Fuel = DIESEL (8 pts)
        vfuel = str(r.get('active_vehicle_fuel', '')).upper()
        if vfuel == 'DIESEL':
            score += 8
            fb.append("Fuel DIESEL [+8]")
        else:
            fb.append(f"Fuel '{vfuel}' — work vans typically run diesel [+0]")

        # C3: Speed in 100-120 km/h (5 pts)
        try:
            spd = int(r.get('active_vehicle_speed', 0))
            if 100 <= spd <= 120:
                score += 5
                fb.append(f"Speed {spd} km/h — work van range [+5]")
            elif 90 <= spd <= 130:
                score += 2
                fb.append(f"Speed {spd} km/h — close [+2]")
            else:
                fb.append(f"Speed {spd} km/h — out of work van range [+0]")
        except (ValueError, TypeError):
            fb.append("Speed parse error [+0]")

        # C4: Route = Fastest (8 pts)
        if rc == '1':
            score += 8
            fb.append("Route Fastest [+8]")
        else:
            fb.append(f"Route '{rc}' — field service needs fastest response [+0]")

        # C5: Avoid tolls = false (7 pts)
        if at == 'false':
            score += 7
            fb.append("Tolls allowed [+7]")
        else:
            fb.append(f"Tolls '{at}' — company pays for toll roads [+0]")

        # C6: Avoid unpaved = false (10 pts — KEY CRITERION)
        if au == 'false':
            score += 10
            fb.append("Unpaved ALLOWED — utility crew needs access [+10]")
        else:
            fb.append(f"Unpaved '{au}' — crew needs unpaved access to infrastructure [+0]")

        # C7: Avoid ferries = true (4 pts — should be kept correct)
        af = str(r.get('avoid_ferries', '')).lower()
        if af == 'true':
            score += 4
            fb.append("Ferries avoided [+4]")
        else:
            fb.append(f"Ferries '{af}' — no ferries needed in Houston [+0]")

        # C8: Arrive-in-direction (5 pts)
        aid = str(r.get('arrive_in_direction', '')).lower()
        if aid == 'true':
            score += 5
            fb.append("Arrive-in-dir ON [+5]")
        else:
            fb.append(f"Arrive-in-dir '{aid}' — safe infrastructure access [+0]")

        # C9: Home near Ship Channel yard (12 pts)
        if home is not None:
            if _coords_ok(home.get('latitude'), home.get('longitude'),
                          EXPECTED_HOME_LAT, EXPECTED_HOME_LON, COORD_TOLERANCE):
                score += 12
                fb.append("Home near Ship Channel yard [+12]")
            else:
                score += 3
                fb.append("Home changed but wrong location [+3]")
        else:
            fb.append("Home not set [+0]")

        # C10: Work near Deer Park (12 pts)
        if work is not None:
            if _coords_ok(work.get('latitude'), work.get('longitude'),
                          EXPECTED_WORK_LAT, EXPECTED_WORK_LON, COORD_TOLERANCE):
                score += 12
                fb.append("Work near Deer Park industrial [+12]")
            else:
                score += 3
                fb.append("Work changed but wrong location [+3]")
        else:
            fb.append("Work not set [+0]")

        # C11: Distance = Miles (5 pts)
        du = str(r.get('distance_units', ''))
        if du == '0':
            score += 5
            fb.append("Miles [+5]")
        else:
            fb.append(f"Distance '{du}' — US operations use miles [+0]")

        # C12: Temperature = Imperial (5 pts)
        tu = str(r.get('temperature_units', ''))
        if tu.lower() == 'imperial':
            score += 5
            fb.append("Fahrenheit [+5]")
        else:
            fb.append(f"Temp '{tu}' — US operations use Imperial [+0]")

        # C13: Time = 12h (4 pts)
        tf = str(r.get('time_format', ''))
        if tf == '1':
            score += 4
            fb.append("12h time [+4]")
        else:
            fb.append(f"Time '{tf}' — US convention is 12h [+0]")

        # C14: Display extras (5 pts)
        bonus = 0
        cs = str(r.get('color_scheme', ''))
        if cs in ('0', '1'):
            bonus += 3

        comp = str(r.get('compass_enabled', '')).lower() if 'compass_enabled' in r else 'false'
        # compass not in export for this task, so skip

        score += bonus
        if bonus > 0:
            fb.append(f"Display extras [+{bonus}]")

        score = min(score, 100)
        passed = score >= PASS_THRESHOLD

        return {"passed": passed, "score": score, "feedback": " | ".join(fb)}

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}
