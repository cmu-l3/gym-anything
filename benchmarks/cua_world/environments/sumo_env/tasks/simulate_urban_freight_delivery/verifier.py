#!/usr/bin/env python3
"""
Verifier for simulate_urban_freight_delivery task.

Programmatic Verification Strategy:
1. Validates the XML syntax and structure of the created pasubio_freight.rou.xml.
2. Validates the modification of run.sumocfg.
3. Parses the resulting tripinfos.xml to prove the route was topologically valid.
4. Checks the freight_report.txt for accurate data extraction.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def safe_float_compare(val1, val2, tol=0.01):
    """Compares two values as floats safely, falling back to string match."""
    try:
        return abs(float(val1) - float(val2)) <= tol
    except (ValueError, TypeError):
        return str(val1).strip() == str(val2).strip()

def verify_simulate_urban_freight_delivery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    pass_threshold = 70
    simulation_succeeded = False

    # Read the exported status JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Criterion 1: Freight XML Validation
    if result.get("has_freight_xml"):
        freight_xml = tempfile.NamedTemporaryFile(delete=False)
        try:
            copy_from_env("/tmp/pasubio_freight.rou.xml", freight_xml.name)
            tree = ET.parse(freight_xml.name)
            root = tree.getroot()

            # Check vType
            vtype = root.find(".//vType[@id='delivery_van']")
            if vtype is not None and vtype.get('vClass') == 'delivery':
                score += 5
                feedback.append("vType delivery_van configured correctly.")
            else:
                feedback.append("Missing or incorrect vType.")

            # Check Vehicle
            vehicle = root.find(".//vehicle[@id='parcel_van_1']")
            if vehicle is not None and vehicle.get('type') == 'delivery_van':
                score += 5
                feedback.append("Vehicle parcel_van_1 configured correctly.")
                
                # Check Route (It can be inline child or referenced)
                route = vehicle.find("route")
                if route is None:
                    route_id = vehicle.get('route')
                    if route_id:
                        route = root.find(f".//route[@id='{route_id}']")
                
                if route is not None:
                    edges = route.get('edges', '').split()
                    if len(edges) >= 4:
                        score += 10
                        feedback.append("Valid route with >= 4 edges found.")
                    else:
                        feedback.append(f"Route has less than 4 edges (found {len(edges)}).")
                else:
                    feedback.append("No route defined for vehicle.")
                
                # Check Stops
                stops = vehicle.findall("stop")
                if not stops and route is not None:
                    # Stops might be defined inside the route instead of vehicle
                    stops = route.findall("stop")

                if len(stops) == 2:
                    s1, s2 = stops[0], stops[1]
                    d1 = s1.get('duration')
                    d2 = s2.get('duration')
                    
                    lane1 = s1.get('lane', '')
                    edge1 = s1.get('edge', '')
                    lane2 = s2.get('lane', '')
                    edge2 = s2.get('edge', '')
                    
                    e1 = edge1 if edge1 else lane1.rsplit('_', 1)[0]
                    e2 = edge2 if edge2 else lane2.rsplit('_', 1)[0]
                    
                    if str(d1) == "60" and str(d2) == "60":
                        if e1 and e2 and e1 != e2:
                            if lane1.endswith('_0') and lane2.endswith('_0'):
                                score += 25
                                feedback.append("Two 60s stops correctly configured on different edges in the rightmost lane.")
                            else:
                                score += 15
                                feedback.append("Stops configured on different edges, but not explicitly on lane _0.")
                        else:
                            score += 10
                            feedback.append("Two 60s stops found, but not on different edges.")
                    else:
                        feedback.append(f"Stops found but duration is not 60 (got {d1}, {d2}).")
                else:
                    feedback.append(f"Expected exactly 2 stops, found {len(stops)}.")
            else:
                feedback.append("Missing or incorrect vehicle parcel_van_1.")

        except Exception as e:
            feedback.append(f"Failed to parse freight XML: {e}")
        finally:
            if os.path.exists(freight_xml.name):
                os.unlink(freight_xml.name)
    else:
        feedback.append("pasubio_freight.rou.xml was not created.")

    # Criterion 2: Config file updated
    if result.get("has_config"):
        sumocfg_file = tempfile.NamedTemporaryFile(delete=False)
        try:
            copy_from_env("/tmp/run.sumocfg", sumocfg_file.name)
            tree = ET.parse(sumocfg_file.name)
            root = tree.getroot()
            
            route_files = root.find(".//route-files")
            add_files = root.find(".//additional-files")
            
            config_ok = False
            if route_files is not None and "pasubio_freight.rou.xml" in route_files.get("value", ""):
                config_ok = True
            elif add_files is not None and "pasubio_freight.rou.xml" in add_files.get("value", ""):
                config_ok = True
                
            if config_ok:
                score += 10
                feedback.append("run.sumocfg correctly updated to load freight XML.")
            else:
                feedback.append("run.sumocfg NOT updated to include pasubio_freight.rou.xml.")
        except Exception as e:
            feedback.append(f"Failed to parse run.sumocfg: {e}")
        finally:
            if os.path.exists(sumocfg_file.name):
                os.unlink(sumocfg_file.name)

    # Criterion 3: Simulation Output Verification (Anti-Gaming)
    actual_duration = None
    actual_route_length = None
    if result.get("has_tripinfos"):
        tripinfos_file = tempfile.NamedTemporaryFile(delete=False)
        try:
            copy_from_env("/tmp/tripinfos.xml", tripinfos_file.name)
            tree = ET.parse(tripinfos_file.name)
            root = tree.getroot()
            trip = root.find(".//tripinfo[@id='parcel_van_1']")
            if trip is not None:
                actual_duration = trip.get("duration")
                actual_route_length = trip.get("routeLength")
                
                if actual_duration and float(actual_duration) > 120:
                    score += 25
                    simulation_succeeded = True
                    feedback.append(f"Simulation succeeded. Tripinfo recorded for parcel_van_1 (Duration: {actual_duration}s).")
                else:
                    feedback.append(f"Tripinfo found, but duration ({actual_duration}s) is too short for two 60s stops.")
            else:
                feedback.append("Tripinfo for parcel_van_1 NOT found. Simulation likely failed due to an invalid route.")
        except Exception as e:
            feedback.append(f"Failed to parse tripinfos.xml (Simulation may not have completed): {e}")
        finally:
            if os.path.exists(tripinfos_file.name):
                os.unlink(tripinfos_file.name)
    else:
        feedback.append("tripinfos.xml was not generated (Simulation did not run successfully).")

    # Criterion 4: Report Accuracy
    if result.get("has_report"):
        report_file = tempfile.NamedTemporaryFile(delete=False)
        try:
            copy_from_env("/tmp/freight_report.txt", report_file.name)
            with open(report_file.name, 'r') as f:
                content = f.read()
            
            report_duration = None
            report_length = None
            for line in content.splitlines():
                line = line.strip()
                if line.startswith("van_trip_duration="):
                    report_duration = line.split("=")[1].strip()
                elif line.startswith("van_route_length="):
                    report_length = line.split("=")[1].strip()
                    
            if actual_duration and actual_route_length:
                if safe_float_compare(report_duration, actual_duration) and safe_float_compare(report_length, actual_route_length):
                    score += 10
                    feedback.append("Report accurately reflects simulation metrics.")
                else:
                    feedback.append(f"Report metrics mismatch. Expected D={actual_duration}, L={actual_route_length}. Got D={report_duration}, L={report_length}.")
            else:
                feedback.append("Report generated, but cannot verify accuracy as simulation metrics were missing.")
                
        except Exception as e:
            feedback.append(f"Failed to process freight_report.txt: {e}")
        finally:
            if os.path.exists(report_file.name):
                os.unlink(report_file.name)
    else:
        feedback.append("freight_report.txt was not created.")

    # Key criteria threshold
    passed = (score >= pass_threshold) and simulation_succeeded

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }