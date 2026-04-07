#!/bin/bash
echo "=== Setting up fix_truss_analyzer task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_truss_analyzer"
PROJECT_DIR="/home/ga/PycharmProjects/truss_analyzer"

# Clean previous runs
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_start_ts /tmp/${TASK_NAME}_result.json 2>/dev/null || true

# Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

# Create directory structure
mkdir -p "$PROJECT_DIR/truss"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/examples"

# --- requirements.txt ---
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
numpy>=1.24.0
pytest>=7.0
EOF

# --- truss/__init__.py ---
touch "$PROJECT_DIR/truss/__init__.py"

# --- truss/node.py ---
cat > "$PROJECT_DIR/truss/node.py" << 'EOF'
"""Node definition for truss structure."""
from dataclasses import dataclass

@dataclass
class Node:
    id: int
    x: float
    y: float
    fx: float = 0.0  # External force X
    fy: float = 0.0  # External force Y
    is_fixed_x: bool = False
    is_fixed_y: bool = False
EOF

# --- truss/materials.py ---
cat > "$PROJECT_DIR/truss/materials.py" << 'EOF'
"""Material properties."""
from dataclasses import dataclass

@dataclass
class Material:
    name: str
    E: float  # Young's Modulus in Pa

# Standard Structural Steel
STEEL_A36 = Material("Steel A36", 200e9)
EOF

# --- truss/element.py ---
# Contains BUG 1 (Area) and BUG 2 (Rotation Matrix)
cat > "$PROJECT_DIR/truss/element.py" << 'EOF'
"""Truss element definition."""
import numpy as np
import math
from truss.node import Node
from truss.materials import Material

class Element:
    def __init__(self, id: int, node1: Node, node2: Node, material: Material, diameter: float):
        self.id = id
        self.n1 = node1
        self.n2 = node2
        self.material = material
        self.diameter = diameter

    @property
    def length(self) -> float:
        return math.sqrt((self.n2.x - self.n1.x)**2 + (self.n2.y - self.n1.y)**2)

    @property
    def angle(self) -> float:
        return math.atan2(self.n2.y - self.n1.y, self.n2.x - self.n1.x)

    @property
    def area(self) -> float:
        """Calculate cross-sectional area of the circular bar."""
        # BUG 1: Calculates circumference instead of area
        # Should be: math.pi * (self.diameter / 2) ** 2
        return math.pi * self.diameter

    def stiffness_matrix(self) -> np.ndarray:
        """Compute the element stiffness matrix in global coordinates."""
        E = self.material.E
        A = self.area
        L = self.length
        
        k = (E * A) / L
        
        # Local stiffness matrix
        k_local = k * np.array([
            [1, 0, -1, 0],
            [0, 0,  0, 0],
            [-1, 0, 1, 0],
            [0, 0,  0, 0]
        ])
        
        c = math.cos(self.angle)
        s = math.sin(self.angle)
        
        # Transformation Matrix
        # BUG 2: Rotation matrix is incorrect (swapped sin/cos terms or signs)
        # The correct 4x4 transformation matrix T should have:
        # [ c  s  0  0 ]
        # [-s  c  0  0 ]
        # ...
        
        # This implementation uses a messed up matrix
        T = np.array([
            [s, c, 0, 0],   # WRONG: should be c, s
            [c, -s, 0, 0],  # WRONG: should be -s, c
            [0, 0, s, c],   # WRONG
            [0, 0, c, -s]   # WRONG
        ])
        
        # K_global = T.T @ k_local @ T
        return T.T @ k_local @ T
EOF

# --- truss/solver.py ---
# Contains BUG 3 (Assembly assignment vs accumulation)
cat > "$PROJECT_DIR/truss/solver.py" << 'EOF'
"""Global stiffness matrix solver."""
import numpy as np
from typing import List
from truss.node import Node
from truss.element import Element

class TrussSolver:
    def __init__(self, nodes: List[Node], elements: List[Element]):
        self.nodes = sorted(nodes, key=lambda n: n.id)
        self.elements = elements
        self.ndof = len(nodes) * 2  # 2 degrees of freedom per node

    def assemble_global_stiffness(self) -> np.ndarray:
        K = np.zeros((self.ndof, self.ndof))
        
        for el in self.elements:
            k_el = el.stiffness_matrix()
            
            # Map local indices to global indices
            # Node 1 DOFs: 2*id, 2*id+1
            # Node 2 DOFs: 2*id, 2*id+1
            # Note: Assuming 0-based node IDs
            idx = [
                2 * el.n1.id, 2 * el.n1.id + 1,
                2 * el.n2.id, 2 * el.n2.id + 1
            ]
            
            # BUG 3: Assignment instead of accumulation
            # This overwrites stiffness contributions from previous elements sharing these nodes
            # Should be: K[np.ix_(idx, idx)] += k_el
            K[np.ix_(idx, idx)] = k_el
            
        return K

    def solve(self):
        K = self.assemble_global_stiffness()
        F = np.zeros(self.ndof)
        
        # Apply force vector
        for i, node in enumerate(self.nodes):
            F[2*i] = node.fx
            F[2*i+1] = node.fy
            
        # Apply boundary conditions (penalty method or reduction)
        # Using reduction method (removing fixed DOFs)
        free_dofs = []
        for i, node in enumerate(self.nodes):
            if not node.is_fixed_x:
                free_dofs.append(2*i)
            if not node.is_fixed_y:
                free_dofs.append(2*i+1)
                
        if not free_dofs:
            return np.zeros(self.ndof)
            
        K_reduced = K[np.ix_(free_dofs, free_dofs)]
        F_reduced = F[free_dofs]
        
        try:
            U_reduced = np.linalg.solve(K_reduced, F_reduced)
        except np.linalg.LinAlgError:
            raise ValueError("Stiffness matrix is singular. Structure is unstable.")
            
        U = np.zeros(self.ndof)
        U[free_dofs] = U_reduced
        
        return U
EOF

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
from truss.node import Node
from truss.element import Element
from truss.materials import STEEL_A36

@pytest.fixture
def basic_triangle_truss():
    """
    Creates a simple 3-node, 3-element truss.
    Nodes: 0(0,0), 1(4,0), 2(0,3) (meters)
    Elements: 0-1 (horizontal), 0-2 (vertical), 2-1 (hypotenuse)
    """
    n0 = Node(0, 0.0, 0.0, is_fixed_x=True, is_fixed_y=True)
    n1 = Node(1, 4.0, 0.0, is_fixed_y=True) # Roller at 1
    n2 = Node(2, 0.0, 3.0, fx=10000.0) # Load at top
    
    nodes = [n0, n1, n2]
    
    # 3-4-5 triangle
    # Element 1: 0-1 (Length 4)
    # Element 2: 0-2 (Length 3)
    # Element 3: 2-1 (Length 5)
    
    diam = 0.05 # 5cm diameter
    
    e1 = Element(0, n0, n1, STEEL_A36, diam)
    e2 = Element(1, n0, n2, STEEL_A36, diam)
    e3 = Element(2, n2, n1, STEEL_A36, diam)
    
    return nodes, [e1, e2, e3]
EOF

# --- tests/test_geometry.py ---
cat > "$PROJECT_DIR/tests/test_geometry.py" << 'EOF'
import math
import pytest
from truss.element import Element
from truss.node import Node
from truss.materials import STEEL_A36

def test_element_length_horizontal():
    n1 = Node(0, 0, 0)
    n2 = Node(1, 3, 0)
    el = Element(0, n1, n2, STEEL_A36, 0.1)
    assert math.isclose(el.length, 3.0)

def test_element_length_inclined():
    n1 = Node(0, 0, 0)
    n2 = Node(1, 3, 4)
    el = Element(0, n1, n2, STEEL_A36, 0.1)
    assert math.isclose(el.length, 5.0)

def test_element_area():
    """Verify cross-sectional area calculation."""
    diameter = 0.1
    n1 = Node(0, 0, 0)
    n2 = Node(1, 1, 0)
    el = Element(0, n1, n2, STEEL_A36, diameter)
    
    expected_area = math.pi * (diameter / 2) ** 2
    # The bug computes area = pi * diameter, which is much larger
    assert math.isclose(el.area, expected_area, rel_tol=1e-5), \
        f"Area incorrect. Expected {expected_area}, got {el.area}"
EOF

# --- tests/test_element.py ---
cat > "$PROJECT_DIR/tests/test_element.py" << 'EOF'
import numpy as np
import math
import pytest
from truss.element import Element
from truss.node import Node
from truss.materials import STEEL_A36

def test_stiffness_matrix_horizontal():
    """Test stiffness matrix for horizontal element (angle = 0)."""
    n1 = Node(0, 0, 0)
    n2 = Node(1, 2, 0)
    diam = 0.02
    el = Element(0, n1, n2, STEEL_A36, diam)
    
    E = STEEL_A36.E
    A = math.pi * (diam/2)**2
    L = 2.0
    k = (E * A) / L
    
    # For horizontal, T is Identity. K_global = K_local
    # [ k  0 -k  0]
    # [ 0  0  0  0]
    # [-k  0  k  0]
    # [ 0  0  0  0]
    
    K = el.stiffness_matrix()
    
    assert math.isclose(K[0,0], k, rel_tol=1e-5)
    assert math.isclose(K[0,2], -k, rel_tol=1e-5)
    assert math.isclose(K[1,1], 0, abs_tol=1e-9)

def test_stiffness_matrix_vertical():
    """Test stiffness matrix for vertical element (angle = 90 deg)."""
    n1 = Node(0, 0, 0)
    n2 = Node(1, 0, 3)
    diam = 0.02
    el = Element(0, n1, n2, STEEL_A36, diam)
    
    E = STEEL_A36.E
    A = math.pi * (diam/2)**2
    L = 3.0
    k = (E * A) / L
    
    # For vertical:
    # [ 0  0  0  0]
    # [ 0  k  0 -k]
    # [ 0  0  0  0]
    # [ 0 -k  0  k]
    
    K = el.stiffness_matrix()
    
    # This will fail if Rotation Matrix T is swapped
    assert math.isclose(K[0,0], 0, abs_tol=1e-9), "K[0,0] should be 0 for vertical bar"
    assert math.isclose(K[1,1], k, rel_tol=1e-5), "K[1,1] should be k for vertical bar"
    assert math.isclose(K[3,3], k, rel_tol=1e-5)

def test_stiffness_matrix_45deg():
    """Test stiffness matrix for 45 degree element."""
    n1 = Node(0, 0, 0)
    n2 = Node(1, 2, 2)
    diam = 0.02
    el = Element(0, n1, n2, STEEL_A36, diam)
    
    E = STEEL_A36.E
    A = math.pi * (diam/2)**2
    L = math.sqrt(8)
    k = (E * A) / L
    
    c = math.cos(math.radians(45)) # 0.707
    s = math.sin(math.radians(45)) # 0.707
    
    # Expected K[0,0] = k * c^2
    # Expected K[0,1] = k * c * s
    
    K = el.stiffness_matrix()
    
    expected_k00 = k * c**2
    
    assert math.isclose(K[0,0], expected_k00, rel_tol=1e-5)
    assert math.isclose(K[0,1], expected_k00, rel_tol=1e-5) # c=s for 45 deg
EOF

# --- tests/test_solver.py ---
cat > "$PROJECT_DIR/tests/test_solver.py" << 'EOF'
import numpy as np
import math
import pytest
from truss.solver import TrussSolver

def test_global_assembly_accumulation(basic_triangle_truss):
    """
    Verify that stiffness matrices are accumulated, not overwritten.
    Node 0 is shared by Element 1 and Element 2.
    """
    nodes, elements = basic_triangle_truss
    solver = TrussSolver(nodes, elements)
    
    K = solver.assemble_global_stiffness()
    
    # Check diagonal for Node 0 (index 0,0 for X-dof)
    # Should contain contribution from Element 1 (horizontal) and Element 2 (vertical)
    
    # Element 1 (0-1): Horizontal (4m)
    # Element 2 (0-2): Vertical (3m)
    
    # E1 contribution to K[0,0] is k1 = EA/L1
    # E2 contribution to K[0,0] is 0 (vertical member has no X stiffness locally, rotation handles it)
    # Actually for vertical member:
    # c=0, s=1. k_local_11 = k * c^2 = 0.
    
    # Let's check Node 2 (index 4,5).
    # Node 2 is connected to Element 2 (0-2, vertical) and Element 3 (2-1, hypotenuse)
    # K[4,4] (Node 2 X) should have contribution from El 2 (0) and El 3 (X component)
    
    # If overwriting happens, one contribution will be lost.
    
    # Just check symmetry as a proxy for basic correctness first
    assert np.allclose(K, K.T, atol=1e-8), "Global stiffness matrix must be symmetric"
    
    # Check that K is not mostly zeros where it shouldn't be
    # Node 0,1,2 are all connected.
    assert K[0,0] > 0
    assert K[5,5] > 0 # Node 2 Y stiffness

def test_solve_simple_tension():
    """Simple 2-node bar in tension."""
    from truss.node import Node
    from truss.element import Element
    from truss.materials import STEEL_A36
    
    # 1 bar, 2m long, pulled by 1000N
    n0 = Node(0, 0, 0, is_fixed_x=True, is_fixed_y=True)
    n1 = Node(1, 2, 0, fx=1000.0)
    
    e1 = Element(0, n0, n1, STEEL_A36, 0.02)
    
    solver = TrussSolver([n0, n1], [e1])
    U = solver.solve()
    
    # F = k * x  => x = F / k = F * L / (EA)
    area = math.pi * (0.01)**2
    k = (STEEL_A36.E * area) / 2.0
    expected_disp = 1000.0 / k
    
    # Node 1 X disp is index 2
    assert math.isclose(U[2], expected_disp, rel_tol=1e-4)

def test_solve_triangle_truss(basic_triangle_truss):
    """
    Solve the triangle truss and check displacements.
    This integrates all fixes (Area, Matrix Rotation, Assembly).
    If Assembly is broken, this result will be wildly wrong.
    """
    nodes, elements = basic_triangle_truss
    solver = TrussSolver(nodes, elements)
    U = solver.solve()
    
    # Check valid displacements
    # Node 0 fixed -> 0,0
    assert math.isclose(U[0], 0)
    assert math.isclose(U[1], 0)
    
    # Node 1 (Roller) -> Fixed Y, Free X
    assert math.isclose(U[3], 0) # Y fixed
    assert U[2] != 0 # X should move
    
    # Node 2 loaded with X force (wait, fixture says fx=10000 on n2? No, fixture says Node 2 fx=0, fy?
    # Fixture: n2 = Node(2, 0.0, 3.0, fx=10000.0) -> Horizontal load at top
    
    # With horizontal load at top, Node 2 should move Right (+)
    assert U[4] > 0
    
    # Verify magnitude is reasonable (order of magnitude)
    # If Area bug exists (Area = pi*D approx 0.15 instead of pi*r^2 approx 0.002)
    # Stiffness will be ~75x too large -> Displacement ~75x too small.
    # If Assembly bug exists -> Stiffness missing -> Displacement too large or singular.
    
    # Expected approx range:
    # L=3m, E=200e9, D=0.05 => A=0.00196
    # k ~ 200e9*0.002/3 ~ 1.3e8
    # F=10000
    # x ~ F/k ~ 1e-4 m
    
    assert 1e-5 < U[4] < 1e-3, f"Displacement {U[4]} out of expected range (approx 1e-4)"
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Wait for PyCharm
wait_for_pycharm 120

# Open project in PyCharm
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /tmp/pycharm_launch.log 2>&1 &"
sleep 10
handle_trust_dialog 5
wait_for_project_loaded "truss_analyzer" 60
dismiss_dialogs 3
focus_pycharm_window

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task Setup Complete ==="