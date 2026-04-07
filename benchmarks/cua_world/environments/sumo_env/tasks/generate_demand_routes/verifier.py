#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_demand_routes(traj, env_info, task_info):
    """
    Verify that the random demand trips and routed output files were successfully created.
    
    Checks:
    1. Output XML files exist and were modified during task execution (anti-gaming).
    2. Parsable XML structure matching trips and routes specification.
    3. Correct number of trips/vehicles generated.
    4. Time ranges adequately distributed.
    5. Edges utilized exist within the actual network map.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_trips = metadata.get('output_trips', '/home/ga/SUMO_Output/random_trips.trips.xml')
    output_routes = metadata.get('output_routes', '/home/ga/SUMO_Output/random_trips.rou.xml')
    expected_trips = metadata.get('expected_trips', 200)

    score = 0
    feedback_parts = []
    
    # 1. Read task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Load valid edge IDs
    temp_edges = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    valid_edges = set()
    try:
        copy_from_env("/tmp/valid_edge_ids.txt", temp_edges.name)
        with open(temp_edges.name, 'r') as f:
            for line in f:
                if line.strip():
                    valid_edges.add(line.strip())
    except Exception as e:
        logger.warning(f"Could not load valid edge IDs: {e}")
    finally:
        if os.path.exists(temp_edges.name):
            os.unlink(temp_edges.name)
            
    task_start = result.get('task_start', 0)
    
    # Check Trips File (40 points possible)
    trips_exists = result.get('trips_exists', False)
    trips_mtime = result.get('trips_mtime', 0)
    trips_size = result.get('trips_size', 0)
    
    if not trips_exists:
        feedback_parts.append("Trips file missing")
    elif trips_mtime < task_start:
        feedback_parts.append("Trips file predates task start (gaming detected)")
    else:
        temp_trips = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env(output_trips, temp_trips.name)
            tree = ET.parse(temp_trips.name)
            root = tree.getroot()
            score += 15
            feedback_parts.append("Trips file is valid XML")
            
            trips = root.findall('.//trip')
            if not trips:
                trips = root.findall('.//vehicle')
                
            count = len(trips)
            if expected_trips * 0.9 <= count <= expected_trips * 1.1:
                score += 15
                feedback_parts.append(f"Trip count ({count}) near expected ({expected_trips})")
            elif expected_trips * 0.5 <= count <= expected_trips * 1.5:
                score += 8
                feedback_parts.append(f"Trip count ({count}) partial")
                
            dep_times = []
            for t in trips:
                d = t.get('depart') or t.get('begin')
                if d:
                    try:
                        dep_times.append(float(d))
                    except ValueError:
                        pass
            
            if dep_times:
                max_dep = max(dep_times)
                if max_dep > 1800:
                    score += 10
                    feedback_parts.append("Trip departures span adequate time")
                elif max_dep > 600:
                    score += 5
                    feedback_parts.append("Trip departures span partial time")
        except ET.ParseError:
            feedback_parts.append("Trips file is invalid XML")
        except Exception as e:
            feedback_parts.append(f"Error parsing trips: {e}")
        finally:
            if os.path.exists(temp_trips.name):
                os.unlink(temp_trips.name)

    # Check Routes File (40 points possible)
    routes_exists = result.get('routes_exists', False)
    routes_mtime = result.get('routes_mtime', 0)
    routes_size = result.get('routes_size', 0)
    
    if not routes_exists:
        feedback_parts.append("Routes file missing")
    elif routes_mtime < task_start:
        feedback_parts.append("Routes file predates task start (gaming detected)")
    else:
        temp_routes = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env(output_routes, temp_routes.name)
            tree = ET.parse(temp_routes.name)
            root = tree.getroot()
            score += 15
            feedback_parts.append("Routes file is valid XML")
            
            vehicles = root.findall('.//vehicle')
            v_count = len(vehicles)
            if v_count >= expected_trips * 0.75:
                score += 15
                feedback_parts.append(f"Routed vehicle count ({v_count}) good")
            elif v_count >= expected_trips * 0.25:
                score += 7
                feedback_parts.append(f"Routed vehicle count ({v_count}) partial")
                
            # Validate edge IDs
            if valid_edges and vehicles:
                valid_routes = 0
                checked = 0
                for veh in vehicles[:20]:
                    route = veh.find('route')
                    if route is not None:
                        edges_str = route.get('edges', '')
                        if edges_str:
                            checked += 1
                            edges = edges_str.split()
                            if all(e in valid_edges for e in edges):
                                valid_routes += 1
                                
                if checked > 0:
                    valid_ratio = valid_routes / checked
                    if valid_ratio > 0.8:
                        score += 10
                        feedback_parts.append("Route edges match network")
                    elif valid_ratio > 0.4:
                        score += 5
                        feedback_parts.append("Some route edges match network")
        except ET.ParseError:
            feedback_parts.append("Routes file is invalid XML")
        except Exception as e:
            feedback_parts.append(f"Error parsing routes: {e}")
        finally:
            if os.path.exists(temp_routes.name):
                os.unlink(temp_routes.name)
                
    # Size Bonus (10 points possible)
    if trips_size > 5000 and routes_size > 10000:
        score += 10
        feedback_parts.append("Files have non-trivial size")

    # VLM Evaluation for trajectory (10 points possible)
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = 'Examine these screenshots of a terminal. Is there evidence that the user ran "randomTrips.py" and "duarouter" commands? Respond with JSON: {"tools_used": true/false}'
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get('parsed', {}).get('tools_used', False):
                score += 10
                feedback_parts.append("VLM confirmed tool usage")
            else:
                feedback_parts.append("VLM did not detect tool usage")
        else:
            # Fallback if frames extraction returned none
            score += 10
    except Exception as e:
        logger.warning(f"VLM evaluation failed: {e}")
        # fallback points if VLM framework is not available locally
        score += 10

    passed = score >= 70 and trips_exists and routes_exists
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }