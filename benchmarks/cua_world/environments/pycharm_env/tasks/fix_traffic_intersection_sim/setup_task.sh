#!/bin/bash
echo "=== Setting up fix_traffic_intersection_sim task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_traffic_intersection_sim"
PROJECT_DIR="/home/ga/PycharmProjects/micro_sim"

# Clean previous state
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_start_ts /tmp/${TASK_NAME}_result.json

# Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/sim $PROJECT_DIR/tests"

# --- requirements.txt ---
cat > "$PROJECT_DIR/requirements.txt" << 'REQUIREMENTS'
pytest>=7.0
REQUIREMENTS

# --- sim/__init__.py ---
touch "$PROJECT_DIR/sim/__init__.py"

# --- sim/core.py (Engine - No bugs) ---
cat > "$PROJECT_DIR/sim/core.py" << 'PYEOF'
"""Core simulation engine definitions."""
from enum import Enum
from dataclasses import dataclass

class SignalState(Enum):
    RED = 0
    GREEN = 1
    AMBER = 2

class TurnDirection(Enum):
    STRAIGHT = 0
    LEFT = 1
    RIGHT = 2

@dataclass
class Position:
    lane_id: str
    offset: float
    
    def distance_to(self, other: 'Position') -> float:
        if self.lane_id != other.lane_id:
            return float('inf')
        return abs(self.offset - other.offset)
PYEOF

# --- sim/vehicle.py (BUG 1: Gap Acceptance) ---
cat > "$PROJECT_DIR/sim/vehicle.py" << 'PYEOF'
"""Vehicle behavior logic."""
from sim.core import Position, TurnDirection

class Vehicle:
    def __init__(self, vid, direction: TurnDirection):
        self.vid = vid
        self.direction = direction
        self.velocity = 0.0
        self.position = None
        self.reaction_time = 1.0  # seconds

    def assess_gap(self, oncoming_vehicle, time_to_arrival: float) -> bool:
        """
        Determine if a gap in oncoming traffic is safe for a left turn.
        
        Args:
            oncoming_vehicle: The nearest oncoming vehicle.
            time_to_arrival: Time (seconds) until oncoming vehicle reaches intersection.
            
        Returns:
            True if safe to turn, False otherwise.
        """
        if self.direction != TurnDirection.LEFT:
            return True
            
        if oncoming_vehicle is None:
            return True
            
        # Critical gap for left turn (standard: 4.5 seconds)
        REQUIRED_GAP = 4.5
        
        # BUG: Logic is inverted or unsafe.
        # It accepts the gap if the oncoming car is closer (time_to_arrival < REQUIRED_GAP)
        # instead of ensuring the oncoming car is far enough away (time_to_arrival > REQUIRED_GAP).
        if time_to_arrival < REQUIRED_GAP:
            return True
            
        return False
PYEOF

# --- sim/signal.py (BUG 2: Missing Amber) ---
cat > "$PROJECT_DIR/sim/signal.py" << 'PYEOF'
"""Traffic signal control logic."""
from sim.core import SignalState

class TrafficSignal:
    def __init__(self, phase_duration_green=30, phase_duration_amber=4):
        self.state = SignalState.RED
        self.timer = 0
        self.green_duration = phase_duration_green
        self.amber_duration = phase_duration_amber

    def set_green(self):
        self.state = SignalState.GREEN
        self.timer = self.green_duration

    def update(self, dt: float):
        """Update signal state based on timer."""
        if self.state == SignalState.RED:
            return # Controlled by external manager

        self.timer -= dt
        
        if self.timer <= 0:
            if self.state == SignalState.GREEN:
                # BUG: Transitions directly to RED, skipping AMBER
                # Should be: self.state = SignalState.AMBER; self.timer = self.amber_duration
                self.state = SignalState.RED
                self.timer = 0
                
            elif self.state == SignalState.AMBER:
                self.state = SignalState.RED
                self.timer = 0
PYEOF

# --- sim/intersection.py (BUG 3: Queue Index Error) ---
cat > "$PROJECT_DIR/sim/intersection.py" << 'PYEOF'
"""Intersection management logic."""
from typing import List, Optional
from sim.vehicle import Vehicle

class IntersectionManager:
    def __init__(self):
        self.queue: List[Vehicle] = []
        self.processed_count = 0

    def add_to_queue(self, vehicle: Vehicle):
        self.queue.append(vehicle)

    def resolve_priority(self) -> Optional[Vehicle]:
        """
        Select the next vehicle to proceed from the queue based on FIFO
        and conflict checks.
        """
        if not self.queue:
            return None

        selected_vehicle = None
        selected_index = -1

        # BUG: Off-by-one error in range prevents checking the last vehicle in the queue.
        # This causes the last vehicle to wait indefinitely (starvation) if it's the only one valid.
        for i in range(len(self.queue) - 1):
            vehicle = self.queue[i]
            # Simple logic: first one found is taken (placeholder for complex logic)
            selected_vehicle = vehicle
            selected_index = i
            break
            
        if selected_vehicle:
            self.queue.pop(selected_index)
            self.processed_count += 1
            
        return selected_vehicle
PYEOF

# --- main.py (Simulation Runner) ---
cat > "$PROJECT_DIR/main.py" << 'PYEOF'
"""
Micro-simulation runner.
Runs a scenario and reports statistics.
"""
import sys
import random
from sim.core import SignalState, TurnDirection
from sim.vehicle import Vehicle
from sim.signal import TrafficSignal
from sim.intersection import IntersectionManager

def run_simulation(duration=60):
    print(f"Starting simulation for {duration}s...")
    
    signal = TrafficSignal()
    intersection = IntersectionManager()
    
    collisions = 0
    violations = 0
    vehicles_completed = 0
    
    # Setup initial state
    signal.set_green()
    
    # Add some vehicles
    v1 = Vehicle("V1", TurnDirection.LEFT)
    v2 = Vehicle("V2", TurnDirection.STRAIGHT) # Oncoming
    v3 = Vehicle("V3", TurnDirection.RIGHT) # Queued
    
    intersection.add_to_queue(v1)
    intersection.add_to_queue(v3)
    
    # Simulation loop
    time = 0
    dt = 1.0
    
    prev_signal_state = signal.state
    
    while time < duration:
        signal.update(dt)
        
        # Check for signal violation (Green -> Red without Amber)
        if prev_signal_state == SignalState.GREEN and signal.state == SignalState.RED:
            print(f"[VIOLATION] Signal switched Green -> Red without Amber at t={time}")
            violations += 1
            
        prev_signal_state = signal.state
        
        # Check collisions (Gap acceptance scenario)
        # Scenario: V1 wants to turn left, V2 is oncoming 3s away
        # REQUIRED_GAP is 4.5s. It is UNSAFE to turn.
        # Buggy logic returns True (Safe), so V1 turns and hits V2.
        if time == 5: # Arbitrary event time
            if v1.assess_gap(v2, time_to_arrival=3.0):
                print(f"[COLLISION] V1 turned left into oncoming V2 at t={time} (Gap: 3.0s < Required: 4.5s)")
                collisions += 1
            else:
                print(f"[INFO] V1 waited correctly for safe gap at t={time}")
        
        # Check priority queue starvation
        # If queue has vehicles but resolve_priority returns None, that's starvation
        # V3 is at end of queue.
        if time > 10 and time % 5 == 0:
            proc = intersection.resolve_priority()
            if proc:
                print(f"[INFO] Processed vehicle {proc.vid}")
                vehicles_completed += 1
                
        time += dt

    print("-" * 30)
    print(f"Simulation Complete")
    print(f"Collisions: {collisions}")
    print(f"Signal Violations: {violations}")
    print(f"Vehicles Completed: {intersection.processed_count}")

if __name__ == "__main__":
    run_simulation()
PYEOF

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
PYEOF

# --- tests/test_safety.py ---
cat > "$PROJECT_DIR/tests/test_safety.py" << 'PYEOF'
from sim.vehicle import Vehicle, TurnDirection

def test_gap_acceptance_rejects_unsafe():
    """Test that left turns are rejected when gap is too small."""
    v = Vehicle("TestV", TurnDirection.LEFT)
    oncoming = Vehicle("Oncoming", TurnDirection.STRAIGHT)
    
    # Gap is 3.0s, Required is 4.5s -> Should return False (Unsafe)
    is_safe = v.assess_gap(oncoming, time_to_arrival=3.0)
    assert is_safe is False, "Vehicle accepted unsafe gap (3.0s < 4.5s)"

def test_gap_acceptance_accepts_safe():
    v = Vehicle("TestV", TurnDirection.LEFT)
    oncoming = Vehicle("Oncoming", TurnDirection.STRAIGHT)
    
    # Gap is 6.0s, Required is 4.5s -> Should return True (Safe)
    is_safe = v.assess_gap(oncoming, time_to_arrival=6.0)
    assert is_safe is True, "Vehicle rejected safe gap (6.0s > 4.5s)"
PYEOF

# --- tests/test_signal.py ---
cat > "$PROJECT_DIR/tests/test_signal.py" << 'PYEOF'
from sim.signal import TrafficSignal, SignalState

def test_signal_transitions_through_amber():
    """Test that signal goes Green -> Amber -> Red."""
    sig = TrafficSignal(phase_duration_green=5, phase_duration_amber=2)
    sig.set_green()
    
    # Advance time to expire Green
    sig.update(5.1)
    
    assert sig.state == SignalState.AMBER, f"Signal should be AMBER after Green expires, got {sig.state}"
    
    # Advance time to expire Amber
    sig.update(2.1)
    
    assert sig.state == SignalState.RED, f"Signal should be RED after Amber expires, got {sig.state}"
PYEOF

# --- tests/test_flow.py ---
cat > "$PROJECT_DIR/tests/test_flow.py" << 'PYEOF'
from sim.intersection import IntersectionManager
from sim.vehicle import Vehicle, TurnDirection

def test_priority_resolution_serves_all():
    """Test that all vehicles in queue are eventually served."""
    im = IntersectionManager()
    v1 = Vehicle("V1", TurnDirection.STRAIGHT)
    v2 = Vehicle("V2", TurnDirection.STRAIGHT)
    
    im.add_to_queue(v1)
    im.add_to_queue(v2)
    
    # Should pop V1
    p1 = im.resolve_priority()
    assert p1 == v1, "First vehicle not processed"
    
    # Should pop V2 (This fails with the off-by-one bug)
    p2 = im.resolve_priority()
    assert p2 == v2, "Second vehicle (end of queue) not processed"
    assert len(im.queue) == 0
PYEOF

# Record start time
echo "$(date +%s)" > /tmp/${TASK_NAME}_start_ts

# Launch PyCharm
echo "Launching PyCharm..."
setup_pycharm_project "$PROJECT_DIR" "micro_sim"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="