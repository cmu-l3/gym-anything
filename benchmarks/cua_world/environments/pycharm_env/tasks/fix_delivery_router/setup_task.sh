#!/bin/bash
echo "=== Setting up fix_delivery_router task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_delivery_router"
PROJECT_DIR="/home/ga/PycharmProjects/route_optimizer"

# Clean up any previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_start_ts /tmp/${TASK_NAME}_result.json 2>/dev/null || true

# Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

# Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/routing $PROJECT_DIR/tests $PROJECT_DIR/data"

# --- 1. Real Data (San Francisco Landmarks) ---
cat > "$PROJECT_DIR/data/locations.csv" << 'CSVEOF'
id,name,latitude,longitude
0,Depot (SoMa),37.7749,-122.4194
1,Golden Gate Bridge,37.8199,-122.4783
2,Fisherman's Wharf,37.8080,-122.4177
3,Alcatraz Landing,37.8066,-122.4048
4,Chase Center,37.7680,-122.3877
5,Oracle Park,37.7786,-122.3893
6,Salesforce Tower,37.7897,-122.3972
7,Twin Peaks,37.7544,-122.4477
8,Painted Ladies,37.7763,-122.4328
9,Coit Tower,37.8024,-122.4058
CSVEOF

# --- 2. routing/__init__.py ---
touch "$PROJECT_DIR/routing/__init__.py"

# --- 3. routing/distance.py (BUG 1: Missing Radians) ---
cat > "$PROJECT_DIR/routing/distance.py" << 'PYEOF'
"""
Geospatial distance calculations.
"""
import math

EARTH_RADIUS_MILES = 3958.8

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate the great circle distance between two points 
    on the earth (specified in decimal degrees).
    """
    # BUG: math.sin expects radians, but inputs are in degrees.
    # Should use: lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    
    dlat = lat2 - lat1
    dlon = lon2 - lon1

    a = math.sin(dlat / 2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    
    return EARTH_RADIUS_MILES * c
PYEOF

# --- 4. routing/solver.py (BUG 2 & 3) ---
cat > "$PROJECT_DIR/routing/solver.py" << 'PYEOF'
"""
Route optimization solver using Nearest Neighbor heuristic.
"""
from typing import List, Dict, Set
import csv
from .distance import haversine_distance

class Location:
    def __init__(self, id: int, name: str, lat: float, lon: float):
        self.id = id
        self.name = name
        self.lat = lat
        self.lon = lon

def load_locations(filepath: str) -> List[Location]:
    locations = []
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            locations.append(Location(
                int(row['id']), 
                row['name'], 
                float(row['latitude']), 
                float(row['longitude'])
            ))
    return locations

class GreedyRouteSolver:
    def __init__(self, locations: List[Location]):
        self.locations = locations
        self.loc_map = {loc.id: loc for loc in locations}

    def solve(self, start_id: int = 0) -> List[int]:
        """
        Generates a route visiting all nodes exactly once using Nearest Neighbor.
        """
        if not self.locations:
            return []
            
        current_id = start_id
        route = [current_id]
        visited = {current_id}
        
        # We need to visit all other nodes
        while len(route) < len(self.locations):
            nearest_dist = float('inf')
            nearest_id = -1
            
            # Find nearest unvisited neighbor
            for candidate in self.locations:
                # BUG: Logic allows looking at current node or doesn't filter strictly enough
                # if candidate.id in visited: continue is missing or flawed
                
                dist = haversine_distance(
                    self.loc_map[current_id].lat, self.loc_map[current_id].lon,
                    candidate.lat, candidate.lon
                )
                
                # BUG: If distance is 0 (self), we might pick it if we don't check visited properly
                # Also, we aren't checking if candidate.id is in visited!
                if dist < nearest_dist and dist > 0: 
                    nearest_dist = dist
                    nearest_id = candidate.id
            
            if nearest_id != -1:
                route.append(nearest_id)
                current_id = nearest_id
                # BUG: We forgot to add nearest_id to visited!
                # visited.add(nearest_id) 
            else:
                # Dead end (shouldn't happen in fully connected graph, but solver might panic)
                break
                
        return route

    def calculate_total_distance(self, route_ids: List[int]) -> float:
        """
        Calculates total distance of the route, including return to depot.
        """
        total_dist = 0.0
        
        # BUG: This loop calculates A->B, B->C, but misses C->A (return to start)
        for i in range(len(route_ids) - 1):
            u = self.loc_map[route_ids[i]]
            v = self.loc_map[route_ids[i+1]]
            total_dist += haversine_distance(u.lat, u.lon, v.lat, v.lon)
            
        return total_dist
PYEOF

# --- 5. Test Suite ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
from routing.solver import Location

@pytest.fixture
def sample_locations():
    return [
        Location(0, "A", 37.7749, -122.4194), # Depot
        Location(1, "B", 37.8199, -122.4783), # ~4 miles away
        Location(2, "C", 37.8080, -122.4177)  # ~2 miles from A
    ]
PYEOF

cat > "$PROJECT_DIR/tests/test_distance.py" << 'PYEOF'
import pytest
import math
from routing.distance import haversine_distance

def test_haversine_same_point():
    # Distance to self should be 0
    assert haversine_distance(37.7749, -122.4194, 37.7749, -122.4194) == 0.0

def test_haversine_accuracy():
    # Known distance: SFO (37.6213, -122.3790) to Golden Gate Bridge (37.8199, -122.4783)
    # Approx 14.5 miles
    d = haversine_distance(37.6213, -122.3790, 37.8199, -122.4783)
    assert 14.0 < d < 15.0, f"Expected ~14.5 miles, got {d}. Did you convert degrees to radians?"

def test_haversine_symmetry():
    d1 = haversine_distance(0, 0, 10, 10)
    d2 = haversine_distance(10, 10, 0, 0)
    assert abs(d1 - d2) < 1e-9
PYEOF

cat > "$PROJECT_DIR/tests/test_solver.py" << 'PYEOF'
import pytest
from routing.solver import GreedyRouteSolver, Location

def test_solver_visits_all_nodes(sample_locations):
    solver = GreedyRouteSolver(sample_locations)
    route = solver.solve(start_id=0)
    assert len(route) == 3
    assert set(route) == {0, 1, 2}

def test_solver_no_duplicates(sample_locations):
    solver = GreedyRouteSolver(sample_locations)
    route = solver.solve(start_id=0)
    assert len(route) == len(set(route)), "Route contains duplicate stops"

def test_solver_structure(sample_locations):
    solver = GreedyRouteSolver(sample_locations)
    route = solver.solve(start_id=0)
    assert route[0] == 0, "Route must start at depot"

def test_return_to_depot_distance(sample_locations):
    # A->C->B (approx tour)
    # A(0,0), B(3,0), C(0,4) for simplicity in mental math, but we use lat/lon
    # We just check that the total distance is > than the path A->B->C
    solver = GreedyRouteSolver(sample_locations)
    route = [0, 2, 1] # A -> C -> B
    
    # Calculate path distance
    u = sample_locations[0]
    v = sample_locations[2]
    w = sample_locations[1]
    
    from routing.distance import haversine_distance
    d1 = haversine_distance(u.lat, u.lon, v.lat, v.lon)
    d2 = haversine_distance(v.lat, v.lon, w.lat, w.lon)
    d3 = haversine_distance(w.lat, w.lon, u.lat, u.lon) # Return leg
    
    expected_total = d1 + d2 + d3
    calculated = solver.calculate_total_distance(route)
    
    # If return leg is missing, calculated will be d1 + d2 only
    assert abs(calculated - expected_total) < 0.1, \
        f"Total distance {calculated} does not match expected loop {expected_total}. Missing return leg?"
PYEOF

# Initialize PyCharm
echo "Launching PyCharm..."
su - ga -c "DISPLAY=:1 nohup /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /tmp/pycharm_startup.log 2>&1 &"

# Wait for PyCharm
wait_for_pycharm 120

# Maximize
focus_pycharm_window

# Initial screenshot
take_screenshot /tmp/fix_delivery_router_initial.png

echo "=== Setup complete ==="