#!/bin/bash
set -e

echo "=== Setting up Delivery Routing Engine Task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Install ortools if missing
if ! python3 -c "import ortools" &> /dev/null; then
    echo "Installing ortools..."
    pip3 install ortools --no-cache-dir
fi

WORKSPACE_DIR="/home/ga/workspace/routing_system"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# 1. Create the realistic VRP Data file
cat > "$WORKSPACE_DIR/data.json" << 'EOF'
{
  "num_vehicles": 3,
  "depot": 0,
  "vehicle_capacities": [15, 15, 15],
  "demands": [0, 5, 5, 5, 5, 5, 5, 5, 5, 2, 2],
  "time_windows": [
    [0, 300],
    [60, 120],
    [150, 200],
    [0, 100],
    [80, 150],
    [200, 280],
    [30, 90],
    [120, 180],
    [160, 220],
    [0, 300],
    [0, 300]
  ],
  "distance_matrix": [
    [0.0, 1.9, 2.5, 3.1, 1.2, 4.5, 2.2, 3.8, 1.5, 2.9, 3.3],
    [1.9, 0.0, 1.1, 2.8, 1.5, 3.2, 1.8, 2.1, 2.5, 1.4, 2.2],
    [2.5, 1.1, 0.0, 1.5, 2.2, 2.5, 3.1, 1.9, 3.5, 1.8, 2.6],
    [3.1, 2.8, 1.5, 0.0, 3.5, 1.8, 4.2, 3.1, 4.5, 2.7, 1.5],
    [1.2, 1.5, 2.2, 3.5, 0.0, 3.8, 1.4, 2.9, 1.8, 2.5, 3.1],
    [4.5, 3.2, 2.5, 1.8, 3.8, 0.0, 4.5, 2.2, 5.1, 3.5, 1.9],
    [2.2, 1.8, 3.1, 4.2, 1.4, 4.5, 0.0, 3.5, 1.2, 2.8, 3.9],
    [3.8, 2.1, 1.9, 3.1, 2.9, 2.2, 3.5, 0.0, 4.1, 1.5, 2.5],
    [1.5, 2.5, 3.5, 4.5, 1.8, 5.1, 1.2, 4.1, 0.0, 3.2, 4.2],
    [2.9, 1.4, 1.8, 2.7, 2.5, 3.5, 2.8, 1.5, 3.2, 0.0, 1.8],
    [3.3, 2.2, 2.6, 1.5, 3.1, 1.9, 3.9, 2.5, 4.2, 1.8, 0.0]
  ],
  "time_matrix": [
    [0, 10, 15, 20, 8, 25, 12, 22, 9, 18, 20],
    [10, 0, 8, 18, 9, 20, 11, 14, 15, 9, 14],
    [15, 8, 0, 10, 14, 15, 18, 12, 20, 11, 15],
    [20, 18, 10, 0, 20, 12, 25, 18, 25, 16, 10],
    [8, 9, 14, 20, 0, 22, 9, 18, 11, 15, 18],
    [25, 20, 15, 12, 22, 0, 28, 14, 30, 20, 12],
    [12, 11, 18, 25, 9, 28, 0, 20, 8, 16, 22],
    [22, 14, 12, 18, 18, 14, 20, 0, 24, 10, 15],
    [9, 15, 20, 25, 11, 30, 8, 24, 0, 18, 25],
    [18, 9, 11, 16, 15, 20, 16, 10, 18, 0, 12],
    [20, 14, 15, 10, 18, 12, 22, 15, 25, 12, 0]
  ]
}
EOF

# 2. Create app.py (DO NOT MODIFY)
cat > "$WORKSPACE_DIR/app.py" << 'EOF'
import json
import sys
from routing_engine import solve_vrp

def main():
    data_file = 'data.json'
    with open(data_file, 'r') as f:
        data = json.load(f)

    result = solve_vrp(data)
    if not result:
        print("No solution found!")
        sys.exit(1)

    solution, routing, manager = result
    
    # Save a flag indicating successful execution
    with open('success.flag', 'w') as f:
        f.write("OK")
        
    print(f"Objective (Total Cost): {solution.ObjectiveValue()}")
    print("Execution successful.")

if __name__ == "__main__":
    main()
EOF

# 3. Create the buggy routing_engine.py
cat > "$WORKSPACE_DIR/routing_engine.py" << 'EOF'
from ortools.constraint_solver import pywrapcp
from ortools.constraint_solver import routing_enums_pb2

def solve_vrp(data):
    manager = pywrapcp.RoutingIndexManager(
        len(data['distance_matrix']),
        data['num_vehicles'],
        data['depot']
    )
    routing = pywrapcp.RoutingModel(manager)

    # 1. Distance Callback
    def distance_callback(from_index, to_index):
        from_node = manager.IndexToNode(from_index)
        to_node = manager.IndexToNode(to_index)
        # BUG 1: Truncates float prematurely. Needs to be multiplied by 100 before int()
        return int(data['distance_matrix'][from_node][to_node])

    transit_callback_index = routing.RegisterTransitCallback(distance_callback)
    routing.SetArcCostEvaluatorOfAllVehicles(transit_callback_index)

    # 2. Demand Callback
    def demand_callback(from_index):
        # BUG 2: Uses routing index instead of node index
        return data['demands'][from_index]

    demand_callback_index = routing.RegisterUnaryTransitCallback(demand_callback)
    routing.AddDimensionWithVehicleCapacity(
        demand_callback_index,
        0,  # null capacity slack
        data['vehicle_capacities'],
        True,
        'Capacity'
    )

    # 3. Time Callback and Dimension
    def time_callback(from_index, to_index):
        from_node = manager.IndexToNode(from_index)
        to_node = manager.IndexToNode(to_index)
        return int(data['time_matrix'][from_node][to_node])

    time_callback_index = routing.RegisterTransitCallback(time_callback)
    
    # BUG 3: slack_max is 0, preventing drivers from waiting for time windows
    routing.AddDimension(
        time_callback_index,
        0,    # slack_max 
        1000, # maximum time per vehicle
        False,
        'Time'
    )
    time_dimension = routing.GetDimensionOrDie('Time')

    # Add Time Window constraints for locations
    for node, time_window in enumerate(data['time_windows']):
        if node == data['depot']:
            continue
        index = manager.NodeToIndex(node)
        time_dimension.CumulVar(index).SetRange(time_window[0], time_window[1])

    # BUG 5: Missing depot return time constraint here!
    # Vehicles need to return before the depot closes.
    

    # BUG 4: Disjunction penalty is too low, causing packages to be dropped
    penalty = 50
    for node in range(1, len(data['distance_matrix'])):
        routing.AddDisjunction([manager.NodeToIndex(node)], penalty)

    # Solve
    search_parameters = pywrapcp.DefaultRoutingSearchParameters()
    search_parameters.first_solution_strategy = routing_enums_pb2.FirstSolutionStrategy.PATH_CHEAPEST_ARC
    solution = routing.SolveWithParameters(search_parameters)

    if not solution:
        return None

    return solution, routing, manager
EOF

chown -R ga:ga "$WORKSPACE_DIR"

# Launch VS Code
if ! pgrep -f "code.*--ms-enable-electron-run-as-node" > /dev/null; then
    echo "Starting VS Code..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR/routing_engine.py &"
    sleep 5
fi

# Wait and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code"; then
        DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="