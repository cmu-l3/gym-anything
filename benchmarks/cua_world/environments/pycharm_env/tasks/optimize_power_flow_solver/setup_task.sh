#!/bin/bash
set -e
echo "=== Setting up optimize_power_flow_solver task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/power_grid_sim"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/power_grid"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/data"

# 1. Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
numpy>=1.24.0
pytest>=7.0
networkx>=3.0
scipy>=1.10.0
EOF

# 2. Generate Synthetic Grid Data Generator
# We create a script to generate consistent test data
cat > "$PROJECT_DIR/data/generate_grid.py" << 'PYEOF'
import json
import random
import networkx as nx
import numpy as np
import math

def generate_case(num_buses, seed=42):
    random.seed(seed)
    np.random.seed(seed)
    
    # Create a small world graph to mimic power grids
    G = nx.watts_strogatz_graph(n=num_buses, k=4, p=0.1, seed=seed)
    
    buses = []
    for i in range(num_buses):
        # Bus types: 0=Load (PQ), 1=Gen (PV), 2=Slack (Ref)
        bus_type = 0
        if i == 0:
            bus_type = 2 # Slack
        elif i < num_buses * 0.1:
            bus_type = 1 # PV
            
        buses.append({
            "id": i,
            "type": bus_type,
            "Pd": round(random.uniform(0.1, 1.5) if bus_type == 0 else 0, 3), # Active Load
            "Qd": round(random.uniform(0.05, 0.5) if bus_type == 0 else 0, 3), # Reactive Load
            "Pg": round(random.uniform(0.5, 2.0) if bus_type == 1 else 0, 3), # Active Gen
            "V_set": 1.05 if bus_type == 2 else (1.02 if bus_type == 1 else 1.0)
        })
    
    lines = []
    for u, v in G.edges():
        # Line impedance
        r = round(random.uniform(0.01, 0.05), 4)
        x = round(random.uniform(0.05, 0.20), 4)
        b = round(random.uniform(0.001, 0.01), 4) # Shunt susceptance
        lines.append({
            "from": u,
            "to": v,
            "r": r,
            "x": x,
            "b": b
        })
        
    return {"buses": buses, "lines": lines, "baseMVA": 100}

# Generate IEEE14-like small case
small_case = generate_case(14, seed=14)
with open("ieee14.json", "w") as f:
    json.dump(small_case, f, indent=2)

# Generate Synthetic 300-bus case (Large enough to be slow with loops)
large_case = generate_case(300, seed=300)
with open("synthetic_grid.json", "w") as f:
    json.dump(large_case, f, indent=2)
PYEOF

# Run data generation
cd "$PROJECT_DIR/data" && python3 generate_grid.py

# 3. Create Slow "Legacy" Implementation

# power_grid/__init__.py
touch "$PROJECT_DIR/power_grid/__init__.py"

# power_grid/admittance.py (Slow Y-bus builder)
cat > "$PROJECT_DIR/power_grid/admittance.py" << 'PYEOF'
import numpy as np

class AdmittanceMatrix:
    def __init__(self, grid_data):
        self.buses = grid_data['buses']
        self.lines = grid_data['lines']
        self.n_buses = len(self.buses)
        
    def build_y_bus(self):
        """
        Build the nodal admittance matrix (Y-bus).
        Legacy implementation: Iterates over lines and updates matrix elements.
        """
        # Initialize complex matrix
        Y = np.zeros((self.n_buses, self.n_buses), dtype=complex)
        
        # Add line admittances
        for line in self.lines:
            i = line['from']
            j = line['to']
            
            # Line series impedance Z = R + jX
            z = complex(line['r'], line['x'])
            # Line series admittance y = 1/Z
            y_series = 1.0 / z
            # Line shunt susceptance (pi-model charging)
            b_shunt = complex(0, line['b'] / 2.0)
            
            # Off-diagonal elements (Yij = -y_series)
            Y[i, j] -= y_series
            Y[j, i] -= y_series
            
            # Diagonal elements (sum of connected admittances + shunts)
            Y[i, i] += (y_series + b_shunt)
            Y[j, j] += (y_series + b_shunt)
            
        return Y
PYEOF

# power_grid/solver.py (Slow Gauss-Seidel)
cat > "$PROJECT_DIR/power_grid/solver.py" << 'PYEOF'
import numpy as np
import cmath

class PowerFlowSolver:
    def __init__(self, grid_data, y_bus):
        self.buses = grid_data['buses']
        self.y_bus = y_bus
        self.n = len(self.buses)
        self.max_iter = 1000
        self.tol = 1e-6
        
    def solve(self):
        """
        Solve power flow using Gauss-Seidel method.
        Legacy implementation: Explicit nested loops over buses.
        """
        # Initialize Voltages (Flat start)
        V = np.ones(self.n, dtype=complex)
        for bus in self.buses:
            if bus['type'] == 2: # Slack
                V[bus['id']] = complex(bus['V_set'], 0)
            elif bus['type'] == 1: # PV
                V[bus['id']] = complex(bus['V_set'], 0)
                
        # Iteration loop
        for it in range(self.max_iter):
            max_error = 0.0
            V_prev = V.copy()
            
            for i in range(self.n):
                bus = self.buses[i]
                bus_type = bus['type']
                
                if bus_type == 2: # Slack bus fixed
                    continue
                
                # Calculate scheduled net power injection S = (Pg - Pd) + j(Qg - Qd)
                # Note: Simple model, ignoring Q limits for PV buses to keep task focused
                P_inj = bus.get('Pg', 0) - bus.get('Pd', 0)
                Q_inj = bus.get('Qg', 0) - bus.get('Qd', 0)
                S_inj = complex(P_inj, Q_inj)
                
                # Summation: sum(Yij * Vj) for all j != i
                sum_yv = complex(0, 0)
                for j in range(self.n):
                    if i != j:
                        sum_yv += self.y_bus[i, j] * V[j]
                
                # Gauss-Seidel update equation:
                # Vi = (1/Yii) * ( (S_inj / Vi* ) - sum(Yij * Vj) )
                Yii = self.y_bus[i, i]
                
                if bus_type == 0: # PQ Bus
                    V[i] = (1.0 / Yii) * ((S_inj.conjugate() / V[i].conjugate()) - sum_yv)
                elif bus_type == 1: # PV Bus
                    # For PV, we estimate Q first
                    # Q_calc = -Imag(Vi* * sum(Yij * Vj))
                    # Simplified for this task: Just treat as PQ but reset magnitude
                    # (Real PV logic is complex, this task focuses on vectorization of the loop structure)
                    temp_V = (1.0 / Yii) * ((S_inj.conjugate() / V[i].conjugate()) - sum_yv)
                    # Enforce voltage magnitude
                    angle = cmath.phase(temp_V)
                    V[i] = cmath.rect(bus['V_set'], angle)
            
            # Check convergence
            diff = np.abs(V - V_prev)
            max_error = np.max(diff)
            
            if max_error < self.tol:
                # print(f"Converged in {it} iterations")
                return V
                
        # print("Did not converge")
        return V
PYEOF

# 4. Create Tests and Benchmark

# tests/test_physics.py
cat > "$PROJECT_DIR/tests/test_physics.py" << 'PYEOF'
import pytest
import json
import numpy as np
import os
from power_grid.admittance import AdmittanceMatrix
from power_grid.solver import PowerFlowSolver

DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'data')

@pytest.fixture
def ieee14_data():
    with open(os.path.join(DATA_DIR, 'ieee14.json')) as f:
        return json.load(f)

def test_y_bus_symmetry(ieee14_data):
    """Y-bus matrix must be symmetric."""
    builder = AdmittanceMatrix(ieee14_data)
    Y = builder.build_y_bus()
    assert np.allclose(Y, Y.T), "Y-bus matrix is not symmetric"

def test_y_bus_diagonal_dominance(ieee14_data):
    """Diagonal elements should roughly equal sum of row (physics check)."""
    builder = AdmittanceMatrix(ieee14_data)
    Y = builder.build_y_bus()
    # Not strictly diagonally dominant in power systems, but checks for non-zero diagonals
    assert np.all(np.abs(np.diag(Y)) > 0), "Found zero diagonal elements"

def test_convergence_small_case(ieee14_data):
    """Solver should converge on the stable IEEE 14 bus case."""
    builder = AdmittanceMatrix(ieee14_data)
    Y = builder.build_y_bus()
    solver = PowerFlowSolver(ieee14_data, Y)
    V = solver.solve()
    
    # Check slack bus voltage
    slack_bus = next(b for b in ieee14_data['buses'] if b['type'] == 2)
    idx = slack_bus['id']
    assert np.isclose(np.abs(V[idx]), slack_bus['V_set']), "Slack bus voltage magnitude drift"
    assert np.isclose(np.angle(V[idx]), 0), "Slack bus angle drift"

def test_kirchhoff_validity(ieee14_data):
    """Check if Current Injections match I = YV."""
    builder = AdmittanceMatrix(ieee14_data)
    Y = builder.build_y_bus()
    solver = PowerFlowSolver(ieee14_data, Y)
    V = solver.solve()
    
    # I = Y * V
    I_calc = Y @ V
    
    # Check power at a load bus P - jQ = V * I_conj
    # S = V * I* -> I = (S/V)*
    for bus in ieee14_data['buses']:
        if bus['type'] == 0: # PQ Bus
            idx = bus['id']
            S_expected = complex(bus.get('Pg',0)-bus['Pd'], bus.get('Qg',0)-bus['Qd'])
            S_calc = V[idx] * I_calc[idx].conjugate()
            # Tolerance is loose because of iterative convergence
            assert np.isclose(S_calc, S_expected, atol=1e-2), f"Power mismatch at bus {idx}"
PYEOF

# benchmark.py
cat > "$PROJECT_DIR/benchmark.py" << 'PYEOF'
import time
import json
import os
import numpy as np
from power_grid.admittance import AdmittanceMatrix
from power_grid.solver import PowerFlowSolver

def run_benchmark():
    data_path = os.path.join('data', 'synthetic_grid.json')
    if not os.path.exists(data_path):
        print("Data file not found")
        return
        
    with open(data_path) as f:
        data = json.load(f)
        
    print(f"Benchmarking with {len(data['buses'])} buses...")
    
    # Measure Y-bus build time
    t0 = time.time()
    builder = AdmittanceMatrix(data)
    Y = builder.build_y_bus()
    t1 = time.time()
    y_bus_time = t1 - t0
    print(f"Y-bus build time: {y_bus_time:.4f}s")
    
    # Measure Solver time
    t0 = time.time()
    solver = PowerFlowSolver(data, Y)
    V = solver.solve()
    t1 = time.time()
    solve_time = t1 - t0
    print(f"Solver time: {solve_time:.4f}s")
    
    total_time = y_bus_time + solve_time
    print(f"Total time: {total_time:.4f}s")
    
    # Save results for verifier
    with open("benchmark_result.json", "w") as f:
        json.dump({
            "y_bus_time": y_bus_time,
            "solve_time": solve_time,
            "total_time": total_time,
            "voltage_sum_real": float(np.sum(V.real)), # Checksum
            "voltage_sum_imag": float(np.sum(V.imag))
        }, f)

if __name__ == "__main__":
    run_benchmark()
PYEOF

# 5. Launch PyCharm
echo "Launching PyCharm..."
source /workspace/scripts/task_utils.sh
setup_pycharm_project "$PROJECT_DIR" "power_grid_sim"

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="