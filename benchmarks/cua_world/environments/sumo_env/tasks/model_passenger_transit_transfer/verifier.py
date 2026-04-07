#!/usr/bin/env python3
"""
Verifier for model_passenger_transit_transfer task.

VERIFICATION METRICS:
1. XML Structure Check: Inspects 'commuters.rou.xml' to verify agent correctly authored
   the required multi-modal `<person>` elements.
2. Config & Execution: Confirms the agent created a functioning `.sumocfg` by running it.
3. Functional Person Output: Parses the ground-truth verification `tripinfo.xml` output 
   to confirm the simulated persons successfully completed their trips.
4. Transfer Success: Validates that the persons physically executed a `<ride>` stage 
   in the simulation (i.e., successfully boarded the requested transit vehicle).
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_passenger_transit_transfer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # 1. Copy JSON result
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            json_temp = f.name
        copy_from_env("/tmp/task_result.json", json_temp)
        with open(json_temp, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        if os.path.exists(json_temp):
            os.unlink(json_temp)

    # 2. Check JSON flags for Config & Simulation Success
    if result.get("sim_success", False):
        score += 40  # Covers Valid Config File + Simulation Completes
        feedback_parts.append("Config valid & simulation ran successfully")
    else:
        feedback_parts.append("Simulation failed or configuration is invalid")

    # 3. Copy and parse the authored commuters.rou.xml
    if result.get("rou_exists", False):
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.xml') as f:
                rou_temp = f.name
            copy_from_env("/home/ga/SUMO_Output/commuters.rou.xml", rou_temp)
            
            tree = ET.parse(rou_temp)
            root = tree.getroot()
            persons = root.findall('.//person')

            valid_persons = 0
            for p in persons:
                tags = [c.tag for c in p]
                # Flexible check: contains at least 2 walks and 1 ride
                if tags.count('walk') >= 2 and tags.count('ride') >= 1:
                    valid_persons += 1

            if valid_persons >= 3:
                score += 20
                feedback_parts.append(f"Commuters XML valid ({valid_persons} intermodal persons authored)")
            else:
                feedback_parts.append(f"Commuters XML invalid: found {valid_persons}/3 valid persons")
        except Exception as e:
            feedback_parts.append("Failed to parse commuters.rou.xml - invalid XML syntax")
        finally:
            if 'rou_temp' in locals() and os.path.exists(rou_temp):
                os.unlink(rou_temp)
    else:
        feedback_parts.append("commuters.rou.xml not found")

    # 4. Copy and parse verifier_tripinfo.xml (anti-gaming metric verification)
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.xml') as f:
            trip_temp = f.name
        copy_from_env("/tmp/verifier_tripinfo.xml", trip_temp)

        if os.path.exists(trip_temp) and os.path.getsize(trip_temp) > 0:
            tree = ET.parse(trip_temp)
            root = tree.getroot()
            pinfos = root.findall('.//personinfo')

            if len(pinfos) >= 3:
                score += 20
                feedback_parts.append(f"Person metrics successfully generated ({len(pinfos)} completed trips)")

                # Check for successful rides within those logs
                successful_rides = 0
                for pinfo in pinfos:
                    if len(pinfo.findall('ride')) > 0:
                        successful_rides += 1

                if successful_rides >= 3:
                    score += 20
                    feedback_parts.append(f"Successful intermodal transfers verified ({successful_rides} rides logged)")
                else:
                    feedback_parts.append(f"Only {successful_rides}/3 intermodal transfers completed")
            else:
                feedback_parts.append(f"Insufficient person metrics in output (found {len(pinfos)}/3)")
        else:
            feedback_parts.append("Verifier tripinfo is empty (persons may not have completed their trips)")
    except Exception as e:
        feedback_parts.append("Failed to verify tripinfo metrics (simulation output missing or malformed)")
    finally:
        if 'trip_temp' in locals() and os.path.exists(trip_temp):
            os.unlink(trip_temp)

    # Require successful completion to pass
    passed = (score >= 80) and result.get("sim_success", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }