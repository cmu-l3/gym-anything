#!/bin/bash
echo "=== Setting up fix_smart_home_hub task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_smart_home_hub"
PROJECT_DIR="/home/ga/PycharmProjects/smarthub"

# Cleanup previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_result.json /tmp/${TASK_NAME}_start_ts 2>/dev/null || true

# Create Project Structure
mkdir -p "$PROJECT_DIR/core"
mkdir -p "$PROJECT_DIR/tests"

# Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
pytest-asyncio>=0.21.0
EOF

# --- core/__init__.py ---
touch "$PROJECT_DIR/core/__init__.py"

# --- core/engine.py (Bug 1: Blocking sleep) ---
cat > "$PROJECT_DIR/core/engine.py" << 'EOF'
import asyncio
import time
import logging

logger = logging.getLogger(__name__)

class AutomationEngine:
    def __init__(self):
        self.running = False
        self.event_queue = asyncio.Queue()

    async def start(self):
        self.running = True
        logger.info("Engine started")

    async def stop(self):
        self.running = False
        logger.info("Engine stopped")

    async def run_scene(self, scene_data: dict):
        """
        Executes a scene which involves a sequence of actions with delays.
        """
        actions = scene_data.get("actions", [])
        logger.info(f"Starting scene with {len(actions)} actions")

        for action in actions:
            action_type = action.get("type")
            
            if action_type == "delay":
                seconds = action.get("seconds", 1.0)
                # BUG: blocking sleep pauses the entire event loop
                time.sleep(seconds)
            
            elif action_type == "device_command":
                # Simulate device command overhead
                await asyncio.sleep(0.01)
                logger.info(f"Executed command: {action.get('command')}")
        
        logger.info("Scene finished")
EOF

# --- core/rules.py (Bug 2: Boolean precedence) ---
cat > "$PROJECT_DIR/core/rules.py" << 'EOF'
class RuleEngine:
    @staticmethod
    def evaluate_trigger(conditions: dict, state: dict) -> bool:
        """
        Evaluates automation triggers based on current home state.
        
        Scenario: "Turn on lights if (Motion detected AND (It is dark OR It is evening))"
        """
        motion = state.get("motion_detected", False)
        dark = state.get("is_dark", False)
        evening = state.get("is_evening", False)

        # BUG: Missing parentheses causing operator precedence error.
        # Python evaluates 'and' before 'or'.
        # If motion=False, dark=False, evening=True -> returns True (Should be False)
        if motion and dark or evening:
            return True
            
        return False
EOF

# --- core/devices.py (Bug 3: Key casing mismatch) ---
cat > "$PROJECT_DIR/core/devices.py" << 'EOF'
class SmartDevice:
    def __init__(self, device_id: str):
        self.device_id = device_id
        self.state = {}

    def update_state(self, payload: dict):
        """
        Updates device state from Zigbee payload.
        """
        self.state.update(payload)


class SmartBulb(SmartDevice):
    def __init__(self, device_id: str):
        super().__init__(device_id)
        self.brightness = 0
        self.color_temp = 2700
        self.is_on = False

    def update_state(self, payload: dict):
        """
        Handle specific bulb attributes.
        Expected payload keys from hardware: 'brightnessLevel', 'colorTemperature', 'onOffStatus'
        """
        super().update_state(payload)
        
        # BUG: Code expects snake_case, but hardware sends camelCase
        if "brightness_level" in payload:
            self.brightness = payload["brightness_level"]
            
        if "color_temperature" in payload:
            self.color_temp = payload["color_temperature"]
            
        if "on_off_status" in payload:
            self.is_on = payload["on_off_status"]
EOF

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
import asyncio

@pytest.fixture
def event_loop():
    """Create an instance of the default event loop for each test case."""
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()
EOF

# --- tests/test_engine.py ---
cat > "$PROJECT_DIR/tests/test_engine.py" << 'EOF'
import pytest
import asyncio
import time
from core.engine import AutomationEngine

@pytest.mark.asyncio
async def test_engine_lifecycle():
    engine = AutomationEngine()
    await engine.start()
    assert engine.running is True
    await engine.stop()
    assert engine.running is False

@pytest.mark.asyncio
async def test_scene_execution_non_blocking():
    """
    Test that running a scene with a delay does not block the event loop.
    We run a parallel 'heartbeat' task. If time.sleep is used, the heartbeat
    will be delayed significantly.
    """
    engine = AutomationEngine()
    
    scene = {
        "actions": [
            {"type": "delay", "seconds": 0.5},
            {"type": "device_command", "command": "turn_on"}
        ]
    }
    
    async def heartbeat():
        # This task should run roughly every 0.1s
        count = 0
        start = time.time()
        while time.time() - start < 0.6:
            await asyncio.sleep(0.1)
            count += 1
        return count

    # Run scene and heartbeat concurrently
    start_time = time.time()
    _, heartbeat_count = await asyncio.gather(
        engine.run_scene(scene),
        heartbeat()
    )
    duration = time.time() - start_time
    
    # Verification
    # 1. Duration should be at least 0.5s (the delay)
    assert duration >= 0.5
    
    # 2. Heartbeat should have run approx 4-6 times during the 0.5s sleep
    # If blocking sleep was used, heartbeat_count would be 0 or 1 (only running after sleep finishes)
    assert heartbeat_count >= 3, f"Event loop was blocked! Heartbeats: {heartbeat_count}"

@pytest.mark.asyncio
async def test_scene_actions_execution():
    engine = AutomationEngine()
    scene = {"actions": [{"type": "device_command", "command": "test"}]}
    # Just ensure it doesn't crash
    await engine.run_scene(scene)
EOF

# --- tests/test_rules.py ---
cat > "$PROJECT_DIR/tests/test_rules.py" << 'EOF'
import pytest
from core.rules import RuleEngine

def test_trigger_basic():
    # Motion and Dark -> True
    state = {"motion_detected": True, "is_dark": True, "is_evening": False}
    assert RuleEngine.evaluate_trigger({}, state) is True

def test_trigger_evening_and_motion():
    # Motion and Evening -> True
    state = {"motion_detected": True, "is_dark": False, "is_evening": True}
    assert RuleEngine.evaluate_trigger({}, state) is True

def test_trigger_just_evening_no_motion():
    # No Motion, Just Evening -> Should be False
    # BUG: Returns True because 'and' binds tighter than 'or'
    # (False and False) or True => True
    state = {"motion_detected": False, "is_dark": False, "is_evening": True}
    assert RuleEngine.evaluate_trigger({}, state) is False, "Trigger fired without motion!"

def test_trigger_no_conditions():
    state = {"motion_detected": False, "is_dark": False, "is_evening": False}
    assert RuleEngine.evaluate_trigger({}, state) is False
EOF

# --- tests/test_devices.py ---
cat > "$PROJECT_DIR/tests/test_devices.py" << 'EOF'
import pytest
from core.devices import SmartBulb

def test_bulb_initial_state():
    bulb = SmartBulb("bulb-1")
    assert bulb.brightness == 0
    assert bulb.is_on is False

def test_bulb_state_update():
    bulb = SmartBulb("bulb-1")
    # Payload simulates incoming Zigbee message (camelCase)
    payload = {
        "brightnessLevel": 255,
        "colorTemperature": 4000,
        "onOffStatus": True
    }
    bulb.update_state(payload)
    
    # Check if internal state updated
    assert bulb.brightness == 255, "Brightness not updated (key mismatch?)"
    assert bulb.color_temp == 4000
    assert bulb.is_on is True

def test_bulb_partial_update():
    bulb = SmartBulb("bulb-1")
    bulb.update_state({"brightnessLevel": 100})
    assert bulb.brightness == 100
    # Others remain default
    assert bulb.is_on is False
EOF

# Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

# Setup PyCharm
source /workspace/scripts/task_utils.sh

# Open PyCharm with the project
echo "Opening PyCharm..."
setup_pycharm_project "$PROJECT_DIR" "smarthub"

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="