#!/bin/bash
set -e
echo "=== Setting up implement_process_controller task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/process_controller"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean any previous attempt
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/controller"
mkdir -p "$PROJECT_DIR/tests"

# --- controller/__init__.py ---
touch "$PROJECT_DIR/controller/__init__.py"

# --- controller/states.py (COMPLETE) ---
cat > "$PROJECT_DIR/controller/states.py" << 'PYEOF'
"""Bottling line process states and events."""
from enum import Enum, auto


class State(Enum):
    IDLE = auto()
    INITIALIZING = auto()
    FILLING = auto()
    SEALING = auto()
    LABELING = auto()
    INSPECTING = auto()
    COMPLETE = auto()
    ERROR = auto()
    EMERGENCY_STOP = auto()


class Event(Enum):
    START = auto()
    INIT_DONE = auto()
    FILL_DONE = auto()
    SEAL_DONE = auto()
    LABEL_DONE = auto()
    INSPECT_PASS = auto()
    INSPECT_FAIL = auto()
    ERROR_DETECTED = auto()
    ERROR_CLEARED = auto()
    EMERGENCY = auto()
    RESET = auto()
PYEOF

# --- controller/machine.py (STUBS) ---
cat > "$PROJECT_DIR/controller/machine.py" << 'PYEOF'
"""Bottling line process controller - Finite State Machine engine."""

from controller.states import State, Event


class InvalidTransitionError(Exception):
    """Raised when no transition is registered for (current_state, event)."""
    pass


class GuardFailedError(Exception):
    """Raised when a transition's guard condition returns False."""
    pass


class StateMachine:
    """Finite State Machine for bottling line process control.

    Manages state transitions, guard conditions, and transition actions
    for an automated bottling line controller.
    """

    def __init__(self, initial_state: State):
        """Initialize the state machine.

        Args:
            initial_state: The starting state of the machine.

        The machine should maintain:
        - current_state: the current State
        - context: a dict for shared process data (starts empty)
        - A transition table mapping (source_state, event) to
          (target_state, guard_fn_or_None, action_fn_or_None)
        - history: a list of (from_state, event, to_state) tuples recording
          every transition that has occurred
        """
        # TODO: Implement
        pass

    def add_transition(self, source, event, target, guard=None, action=None):
        """Register a state transition.

        Args:
            source: State from which this transition is valid.
            event: Event that triggers this transition.
            target: State to transition to.
            guard: Optional callable(context, **kwargs) -> bool.
                   Transition only proceeds if guard returns True.
            action: Optional callable(context, **kwargs) executed
                    during the transition (after guard check, before
                    state is updated).
        """
        # TODO: Implement
        pass

    def process_event(self, event, **kwargs):
        """Process an incoming event, potentially transitioning states.

        Algorithm:
        1. Look up (current_state, event) in the transition table.
        2. If no transition registered, raise InvalidTransitionError.
        3. If a guard is registered, call guard(self.context, **kwargs).
           If it returns False, raise GuardFailedError.
        4. If an action is registered, call action(self.context, **kwargs).
        5. Record (old_state, event, new_state) in history.
        6. Update current_state to target.

        Args:
            event: Event to process.
            **kwargs: Passed through to guard and action callables.

        Raises:
            InvalidTransitionError: No transition for (current_state, event).
            GuardFailedError: Guard returned False.

        Returns:
            The new current state after transition.
        """
        # TODO: Implement
        pass

    def get_current_state(self):
        """Return the current State."""
        # TODO: Implement
        pass

    def get_transition_history(self):
        """Return list of (from_state, event, to_state) tuples."""
        # TODO: Implement
        pass

    def can_process(self, event, **kwargs):
        """Check if event can be processed without actually transitioning.

        Returns True if:
        - A transition exists for (current_state, event), AND
        - The guard (if any) returns True when called with current context.

        Returns False otherwise (never raises).

        Args:
            event: Event to check.
            **kwargs: Passed to guard if present.
        """
        # TODO: Implement
        pass
PYEOF

# --- controller/guards.py (STUBS) ---
cat > "$PROJECT_DIR/controller/guards.py" << 'PYEOF'
"""Guard functions for bottling line state transitions.

Each guard receives the machine's context dict and optional kwargs,
and returns True if the transition should be allowed, False otherwise.
If a required key is missing from context or kwargs, return False.
"""


def check_temperature(context, **kwargs):
    """Allow transition only if filling temperature is 2.0-8.0 deg C inclusive.

    Reads 'temperature' from context.
    Returns False if key is missing or value is out of range.
    """
    # TODO: Implement
    pass


def check_pressure(context, **kwargs):
    """Allow transition only if line pressure is 1.0-3.0 bar inclusive.

    Reads 'pressure' from context.
    Returns False if key is missing or value is out of range.
    """
    # TODO: Implement
    pass


def check_fill_level(context, **kwargs):
    """Allow transition only if fill level is 0.95-1.05 inclusive (ratio of target).

    Reads 'fill_level' from kwargs.
    Returns False if key is missing or value is out of range.
    """
    # TODO: Implement
    pass


def check_label_aligned(context, **kwargs):
    """Allow transition only if label alignment offset is < 2.0 mm (strict less-than).

    Reads 'alignment_offset_mm' from kwargs.
    Returns False if key is missing or value is out of range.
    """
    # TODO: Implement
    pass


def check_seal_integrity(context, **kwargs):
    """Allow transition only if seal torque is 1.5-3.0 Nm inclusive.

    Reads 'seal_torque_nm' from kwargs.
    Returns False if key is missing or value is out of range.
    """
    # TODO: Implement
    pass
PYEOF

# --- controller/actions.py (STUBS) ---
cat > "$PROJECT_DIR/controller/actions.py" << 'PYEOF'
"""State transition action handlers for the bottling line controller.

Each action receives the machine's context dict and optional kwargs,
and modifies the context in-place.
"""


def on_enter_filling(context, **kwargs):
    """Execute when transitioning into FILLING state.

    Sets:
        context["pump_active"] = True
        context["fill_start_time"] = kwargs.get("timestamp", 0)
    """
    # TODO: Implement
    pass


def on_exit_filling(context, **kwargs):
    """Execute when transitioning out of FILLING state.

    Sets:
        context["pump_active"] = False
        context["total_filled"] = context.get("total_filled", 0) + 1
    """
    # TODO: Implement
    pass


def on_enter_error(context, **kwargs):
    """Execute when transitioning into ERROR state.

    Sets:
        context["error_code"] = kwargs.get("error_code", "UNKNOWN")
        context["error_count"] = context.get("error_count", 0) + 1
    """
    # TODO: Implement
    pass


def on_enter_emergency_stop(context, **kwargs):
    """Execute when transitioning into EMERGENCY_STOP state.

    Sets:
        context["pump_active"] = False
        context["conveyor_active"] = False
        context["emergency_timestamp"] = kwargs.get("timestamp", 0)
    """
    # TODO: Implement
    pass
PYEOF

# --- tests/__init__.py ---
touch "$PROJECT_DIR/tests/__init__.py"

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
"""Fixtures for bottling line controller tests."""
import pytest
from controller.states import State, Event
from controller.machine import StateMachine
from controller.guards import (
    check_temperature, check_pressure, check_fill_level,
    check_label_aligned, check_seal_integrity,
)
from controller.actions import (
    on_enter_filling, on_exit_filling,
    on_enter_error, on_enter_emergency_stop,
)


def combined_guard(*guards):
    """Create a guard that requires ALL sub-guards to pass."""
    def _check(context, **kwargs):
        return all(g(context, **kwargs) for g in guards)
    return _check


@pytest.fixture
def bare_machine():
    """A StateMachine with no transitions registered (starts IDLE)."""
    return StateMachine(State.IDLE)


@pytest.fixture
def simple_machine():
    """A machine with the happy-path transitions, NO guards or actions."""
    m = StateMachine(State.IDLE)
    m.add_transition(State.IDLE, Event.START, State.INITIALIZING)
    m.add_transition(State.INITIALIZING, Event.INIT_DONE, State.FILLING)
    m.add_transition(State.FILLING, Event.FILL_DONE, State.SEALING)
    m.add_transition(State.SEALING, Event.SEAL_DONE, State.LABELING)
    m.add_transition(State.LABELING, Event.LABEL_DONE, State.INSPECTING)
    m.add_transition(State.INSPECTING, Event.INSPECT_PASS, State.COMPLETE)
    m.add_transition(State.INSPECTING, Event.INSPECT_FAIL, State.ERROR)
    m.add_transition(State.ERROR, Event.ERROR_CLEARED, State.IDLE)
    m.add_transition(State.COMPLETE, Event.RESET, State.IDLE)
    return m


@pytest.fixture
def guarded_machine():
    """A machine with guards on transitions that require sensor checks."""
    m = StateMachine(State.IDLE)
    m.add_transition(State.IDLE, Event.START, State.INITIALIZING)
    m.add_transition(
        State.INITIALIZING, Event.INIT_DONE, State.FILLING,
        guard=combined_guard(check_temperature, check_pressure),
        action=on_enter_filling,
    )
    m.add_transition(
        State.FILLING, Event.FILL_DONE, State.SEALING,
        guard=check_fill_level,
        action=on_exit_filling,
    )
    m.add_transition(
        State.SEALING, Event.SEAL_DONE, State.LABELING,
        guard=check_seal_integrity,
    )
    m.add_transition(
        State.LABELING, Event.LABEL_DONE, State.INSPECTING,
        guard=check_label_aligned,
    )
    m.add_transition(State.INSPECTING, Event.INSPECT_PASS, State.COMPLETE)
    m.add_transition(
        State.INSPECTING, Event.INSPECT_FAIL, State.ERROR,
        action=on_enter_error,
    )
    m.add_transition(State.ERROR, Event.ERROR_CLEARED, State.IDLE)
    m.add_transition(State.COMPLETE, Event.RESET, State.IDLE)
    # Emergency stop reachable from operational states
    for src in [State.IDLE, State.INITIALIZING, State.FILLING,
                State.SEALING, State.LABELING, State.INSPECTING,
                State.ERROR, State.COMPLETE]:
        m.add_transition(src, Event.EMERGENCY, State.EMERGENCY_STOP,
                         action=on_enter_emergency_stop)
    m.add_transition(State.EMERGENCY_STOP, Event.RESET, State.IDLE)
    return m
PYEOF

# --- tests/test_transitions.py ---
cat > "$PROJECT_DIR/tests/test_transitions.py" << 'PYEOF'
"""Tests for basic state machine transition logic."""
import pytest
from controller.states import State, Event
from controller.machine import StateMachine, InvalidTransitionError


class TestBasicTransitions:
    """Tests that the FSM engine correctly transitions between states."""

    def test_initial_state(self, bare_machine):
        assert bare_machine.get_current_state() == State.IDLE

    def test_single_transition(self, simple_machine):
        result = simple_machine.process_event(Event.START)
        assert result == State.INITIALIZING
        assert simple_machine.get_current_state() == State.INITIALIZING

    def test_happy_path_full_cycle(self, simple_machine):
        """Walk the entire happy path: IDLE -> ... -> COMPLETE -> IDLE."""
        simple_machine.process_event(Event.START)
        simple_machine.process_event(Event.INIT_DONE)
        simple_machine.process_event(Event.FILL_DONE)
        simple_machine.process_event(Event.SEAL_DONE)
        simple_machine.process_event(Event.LABEL_DONE)
        simple_machine.process_event(Event.INSPECT_PASS)
        assert simple_machine.get_current_state() == State.COMPLETE
        simple_machine.process_event(Event.RESET)
        assert simple_machine.get_current_state() == State.IDLE

    def test_invalid_transition_raises(self, simple_machine):
        """IDLE + FILL_DONE should raise InvalidTransitionError."""
        with pytest.raises(InvalidTransitionError):
            simple_machine.process_event(Event.FILL_DONE)

    def test_inspect_fail_goes_to_error(self, simple_machine):
        simple_machine.process_event(Event.START)
        simple_machine.process_event(Event.INIT_DONE)
        simple_machine.process_event(Event.FILL_DONE)
        simple_machine.process_event(Event.SEAL_DONE)
        simple_machine.process_event(Event.LABEL_DONE)
        simple_machine.process_event(Event.INSPECT_FAIL)
        assert simple_machine.get_current_state() == State.ERROR

    def test_error_cleared_returns_to_idle(self, simple_machine):
        simple_machine.process_event(Event.START)
        simple_machine.process_event(Event.INIT_DONE)
        simple_machine.process_event(Event.FILL_DONE)
        simple_machine.process_event(Event.SEAL_DONE)
        simple_machine.process_event(Event.LABEL_DONE)
        simple_machine.process_event(Event.INSPECT_FAIL)
        simple_machine.process_event(Event.ERROR_CLEARED)
        assert simple_machine.get_current_state() == State.IDLE

    def test_history_records_all_transitions(self, simple_machine):
        simple_machine.process_event(Event.START)
        simple_machine.process_event(Event.INIT_DONE)
        history = simple_machine.get_transition_history()
        assert len(history) == 2
        assert history[0] == (State.IDLE, Event.START, State.INITIALIZING)
        assert history[1] == (State.INITIALIZING, Event.INIT_DONE, State.FILLING)

    def test_history_empty_initially(self, bare_machine):
        assert bare_machine.get_transition_history() == []
PYEOF

# --- tests/test_guards.py ---
cat > "$PROJECT_DIR/tests/test_guards.py" << 'PYEOF'
"""Tests for guard conditions on state transitions."""
import pytest
from controller.states import State, Event
from controller.machine import GuardFailedError


class TestGuards:
    """Tests that guard functions correctly gate transitions."""

    def test_init_done_passes_with_valid_temp_and_pressure(self, guarded_machine):
        guarded_machine.process_event(Event.START)
        guarded_machine.context["temperature"] = 4.0
        guarded_machine.context["pressure"] = 2.0
        result = guarded_machine.process_event(Event.INIT_DONE)
        assert result == State.FILLING

    def test_init_done_fails_with_high_temperature(self, guarded_machine):
        guarded_machine.process_event(Event.START)
        guarded_machine.context["temperature"] = 12.0  # Too hot
        guarded_machine.context["pressure"] = 2.0
        with pytest.raises(GuardFailedError):
            guarded_machine.process_event(Event.INIT_DONE)
        assert guarded_machine.get_current_state() == State.INITIALIZING

    def test_fill_done_passes_with_level_in_tolerance(self, guarded_machine):
        guarded_machine.process_event(Event.START)
        guarded_machine.context["temperature"] = 5.0
        guarded_machine.context["pressure"] = 2.0
        guarded_machine.process_event(Event.INIT_DONE)
        result = guarded_machine.process_event(Event.FILL_DONE, fill_level=1.00)
        assert result == State.SEALING

    def test_fill_done_fails_with_underfill(self, guarded_machine):
        guarded_machine.process_event(Event.START)
        guarded_machine.context["temperature"] = 5.0
        guarded_machine.context["pressure"] = 2.0
        guarded_machine.process_event(Event.INIT_DONE)
        with pytest.raises(GuardFailedError):
            guarded_machine.process_event(Event.FILL_DONE, fill_level=0.80)
        assert guarded_machine.get_current_state() == State.FILLING

    def test_can_process_returns_true_when_guard_passes(self, guarded_machine):
        guarded_machine.process_event(Event.START)
        guarded_machine.context["temperature"] = 5.0
        guarded_machine.context["pressure"] = 2.0
        assert guarded_machine.can_process(Event.INIT_DONE) is True

    def test_can_process_returns_false_when_guard_fails(self, guarded_machine):
        guarded_machine.process_event(Event.START)
        guarded_machine.context["temperature"] = 0.5  # Too cold
        guarded_machine.context["pressure"] = 2.0
        assert guarded_machine.can_process(Event.INIT_DONE) is False
        # State should NOT have changed
        assert guarded_machine.get_current_state() == State.INITIALIZING
PYEOF

# --- tests/test_actions.py ---
cat > "$PROJECT_DIR/tests/test_actions.py" << 'PYEOF'
"""Tests for entry/exit action handlers on transitions."""
import pytest
from controller.states import State, Event
from controller.machine import GuardFailedError


class TestActions:
    """Tests that action callbacks correctly modify the context."""

    def test_enter_filling_activates_pump(self, guarded_machine):
        guarded_machine.process_event(Event.START)
        guarded_machine.context["temperature"] = 5.0
        guarded_machine.context["pressure"] = 2.0
        guarded_machine.process_event(Event.INIT_DONE, timestamp=1000)
        assert guarded_machine.context["pump_active"] is True
        assert guarded_machine.context["fill_start_time"] == 1000

    def test_exit_filling_deactivates_pump_and_increments_count(self, guarded_machine):
        guarded_machine.process_event(Event.START)
        guarded_machine.context["temperature"] = 5.0
        guarded_machine.context["pressure"] = 2.0
        guarded_machine.process_event(Event.INIT_DONE, timestamp=1000)
        assert guarded_machine.context["pump_active"] is True
        guarded_machine.process_event(Event.FILL_DONE, fill_level=1.0)
        assert guarded_machine.context["pump_active"] is False
        assert guarded_machine.context["total_filled"] == 1

    def test_total_filled_accumulates_across_cycles(self, guarded_machine):
        """Run two complete fill cycles, total_filled should be 2."""
        for _ in range(2):
            guarded_machine.process_event(Event.START)
            guarded_machine.context["temperature"] = 5.0
            guarded_machine.context["pressure"] = 2.0
            guarded_machine.process_event(Event.INIT_DONE, timestamp=1000)
            guarded_machine.process_event(Event.FILL_DONE, fill_level=1.0)
            guarded_machine.process_event(Event.SEAL_DONE, seal_torque_nm=2.0)
            guarded_machine.process_event(Event.LABEL_DONE, alignment_offset_mm=0.5)
            guarded_machine.process_event(Event.INSPECT_PASS)
            guarded_machine.process_event(Event.RESET)
        assert guarded_machine.context["total_filled"] == 2

    def test_enter_error_sets_error_code_and_count(self, guarded_machine):
        guarded_machine.process_event(Event.START)
        guarded_machine.context["temperature"] = 5.0
        guarded_machine.context["pressure"] = 2.0
        guarded_machine.process_event(Event.INIT_DONE)
        guarded_machine.process_event(Event.FILL_DONE, fill_level=1.0)
        guarded_machine.process_event(Event.SEAL_DONE, seal_torque_nm=2.0)
        guarded_machine.process_event(Event.LABEL_DONE, alignment_offset_mm=0.5)
        guarded_machine.process_event(Event.INSPECT_FAIL, error_code="LABEL_CROOKED")
        assert guarded_machine.context["error_code"] == "LABEL_CROOKED"
        assert guarded_machine.context["error_count"] == 1

    def test_enter_error_default_code_is_unknown(self, guarded_machine):
        guarded_machine.process_event(Event.START)
        guarded_machine.context["temperature"] = 5.0
        guarded_machine.context["pressure"] = 2.0
        guarded_machine.process_event(Event.INIT_DONE)
        guarded_machine.process_event(Event.FILL_DONE, fill_level=1.0)
        guarded_machine.process_event(Event.SEAL_DONE, seal_torque_nm=2.0)
        guarded_machine.process_event(Event.LABEL_DONE, alignment_offset_mm=0.5)
        guarded_machine.process_event(Event.INSPECT_FAIL)
        assert guarded_machine.context["error_code"] == "UNKNOWN"

    def test_emergency_stop_disables_all_actuators(self, guarded_machine):
        guarded_machine.process_event(Event.START)
        guarded_machine.context["temperature"] = 5.0
        guarded_machine.context["pressure"] = 2.0
        guarded_machine.process_event(Event.INIT_DONE, timestamp=500)
        # Pump should be active in FILLING
        assert guarded_machine.context["pump_active"] is True
        guarded_machine.context["conveyor_active"] = True
        guarded_machine.process_event(Event.EMERGENCY, timestamp=999)
        assert guarded_machine.get_current_state() == State.EMERGENCY_STOP
        assert guarded_machine.context["pump_active"] is False
        assert guarded_machine.context["conveyor_active"] is False
        assert guarded_machine.context["emergency_timestamp"] == 999
PYEOF

# --- requirements.txt ---
cat > "$PROJECT_DIR/requirements.txt" << 'PYEOF'
pytest>=7.0
PYEOF

# Calculate hash of test files for anti-gaming verification
md5sum "$PROJECT_DIR/tests/"*.py > /tmp/initial_test_hashes.txt

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Wait for PyCharm and open project
wait_for_pycharm 60 || echo "WARNING: PyCharm not detected"

# Open the project in PyCharm (using task_utils helper)
setup_pycharm_project "$PROJECT_DIR" "process_controller" 120

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="