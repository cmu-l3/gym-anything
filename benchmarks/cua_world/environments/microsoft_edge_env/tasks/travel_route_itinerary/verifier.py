#!/usr/bin/env python3
"""
Verifier for Travel Route Itinerary Research task.

Scoring (100 points):
- File Existence & Anti-Gaming (10 pts)
- Content: Client Name (4 pts), Origin/Dest (16 pts)
- Logistics: Distance (12 pts), Time (12 pts)
- Waypoints: 3+ Real PCH stops (16 pts)
- Weather: Weather terms present (10 pts)
- Research: Map & Weather sites visited (15 pts)
- Completeness: File size > 200 chars (5 pts)

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_travel_route_itinerary(traj, env_info, task_info):
    """Verify the Travel Route Itinerary task."""
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    result_path = "/tmp/task_result.json"
    local_result_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json").name
    
    # Load itinerary file content
    itinerary_path = "/home/ga/Desktop/pacific_coast_itinerary.txt"
    local_itinerary_file = tempfile.NamedTemporaryFile(delete=False, suffix=".txt").name

    try:
        copy_from_env(result_path, local_result_file)
        with open(local_result_file, "r") as f:
            result_data = json.load(f)
            
        itinerary_info = result_data.get("itinerary", {})
        history_urls = result_data.get("history", [])
        
        # Try to copy the text file if it exists
        itinerary_content = ""
        if itinerary_info.get("exists"):
            try:
                copy_from_env(itinerary_path, local_itinerary_file)
                with open(local_itinerary_file, "r", errors="ignore") as f:
                    itinerary_content = f.read()
            except Exception as e:
                logger.warning(f"Could not copy itinerary file: {e}")
                
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading verification data: {e}"}
    finally:
        if os.path.exists(local_result_file): os.unlink(local_result_file)
        if os.path.exists(local_itinerary_file): os.unlink(local_itinerary_file)

    # 2. Scoring Logic
    score = 0
    feedback = []
    metadata = task_info.get("metadata", {})
    
    # --- Criterion 1: File Existence & Validity (10 pts) ---
    if itinerary_info.get("exists") and itinerary_info.get("created_during_task"):
        score += 10
        feedback.append("Itinerary file created successfully.")
    elif itinerary_info.get("exists"):
        score += 5
        feedback.append("Itinerary file exists but timestamp is old (possible pre-existing file).")
    else:
        return {"passed": False, "score": 0, "feedback": "Itinerary file not found."}

    content_lower = itinerary_content.lower()

    # --- Criterion 2: Completeness check (5 pts) ---
    if len(content_lower) > 200:
        score += 5
        feedback.append("File content length is sufficient.")
    else:
        feedback.append("File content is too short.")

    # --- Criterion 3: Client & Route Details (20 pts) ---
    if "margaret" in content_lower or "chen" in content_lower:
        score += 4
        feedback.append("Client name found.")
    
    if "san francisco" in content_lower or " sf " in content_lower:
        score += 8
    
    if "los angeles" in content_lower or " la " in content_lower:
        score += 8

    # --- Criterion 4: Logistics Data (24 pts) ---
    # Look for distance (e.g., 380 miles, 450 mi, 600 km)
    if re.search(r'\d+\s*(miles|mi|km)', content_lower):
        score += 12
        feedback.append("Driving distance found.")
    else:
        feedback.append("Missing driving distance.")

    # Look for time (e.g., 8 hours, 9 hrs, 10 h, 40 mins)
    if re.search(r'\d+\s*(hours|hrs|h)', content_lower):
        score += 12
        feedback.append("Driving time found.")
    else:
        feedback.append("Missing driving time.")

    # --- Criterion 5: Waypoints (16 pts) ---
    pch_waypoints = [w.lower() for w in metadata.get("pch_waypoints", [])]
    found_waypoints = [w for w in pch_waypoints if w in content_lower]
    
    if len(found_waypoints) >= 3:
        score += 16
        feedback.append(f"Found {len(found_waypoints)} waypoints: {', '.join(found_waypoints[:3])}...")
    elif len(found_waypoints) > 0:
        partial_score = int(16 * (len(found_waypoints) / 3))
        score += partial_score
        feedback.append(f"Found only {len(found_waypoints)} waypoints (expected 3).")
    else:
        feedback.append("No known PCH waypoints found.")

    # --- Criterion 6: Weather Info (10 pts) ---
    weather_terms = ["weather", "temperature", "forecast", "sunny", "cloudy", "rain", "degrees", "fahrenheit", "celsius"]
    if any(term in content_lower for term in weather_terms):
        score += 10
        feedback.append("Weather information found.")
    else:
        feedback.append("Missing weather information.")

    # --- Criterion 7: Browser History / Research verification (15 pts) ---
    map_domains = metadata.get("map_domains", ["google.com/maps", "bing.com/maps"])
    weather_domains = metadata.get("weather_domains", ["weather.com", "weather.gov"])
    
    visited_maps = any(any(d in item['url'] for d in map_domains) for item in history_urls)
    visited_weather = any(any(d in item['url'] for d in weather_domains) for item in history_urls)
    
    if visited_maps:
        score += 10
        feedback.append("Verified visit to map service.")
    else:
        feedback.append("No map service visit detected in history.")
        
    if visited_weather:
        score += 5
        feedback.append("Verified visit to weather service.")
    else:
        feedback.append("No weather service visit detected in history.")

    # Final Result
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }