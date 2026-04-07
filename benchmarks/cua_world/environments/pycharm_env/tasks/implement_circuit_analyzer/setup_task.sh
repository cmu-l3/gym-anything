#!/bin/bash
echo "=== Setting up implement_circuit_analyzer task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/circuit_analyzer"
TASK_START_TS=$(date +%s)
echo "$TASK_START_TS" > /tmp/task_start_time.txt

# Clean previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/circuit_analyzer_result.json 2>/dev/null || true

# Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/circuits $PROJECT_DIR/tests"

# --- Create Source Files (Stubs) ---

# circuits/__init__.py
touch "$PROJECT_DIR/circuits/__init__.py"

# circuits/components.py
cat > "$PROJECT_DIR/circuits/components.py" << 'PYEOF'
import cmath
import math
from abc import ABC, abstractmethod

class Component(ABC):
    """Base class for circuit components."""
    def __init__(self, value: float, name: str = ""):
        self.value = value  # ohms, farads, or henries
        self.name = name

    @abstractmethod
    def impedance(self, freq: float) -> complex:
        """Return complex impedance at given frequency (Hz)."""
        pass

class Resistor(Component):
    """Resistor: Z = R (pure real, frequency-independent)."""
    def impedance(self, freq: float) -> complex:
        return complex(self.value, 0)

class Capacitor(Component):
    """Capacitor: Z = 1 / (j * 2π * f * C)."""
    def impedance(self, freq: float) -> complex:
        # TODO: Implement this
        raise NotImplementedError("Implement capacitor impedance")

class Inductor(Component):
    """Inductor: Z = j * 2π * f * L."""
    def impedance(self, freq: float) -> complex:
        # TODO: Implement this
        raise NotImplementedError("Implement inductor impedance")
PYEOF

# circuits/networks.py
cat > "$PROJECT_DIR/circuits/networks.py" << 'PYEOF'
import cmath

def series_impedance(impedances: list[complex]) -> complex:
    """Total impedance of components in series: Z_total = Z1 + Z2 + ..."""
    # TODO: Implement this
    raise NotImplementedError

def parallel_impedance(impedances: list[complex]) -> complex:
    """Total impedance of components in parallel: 1/Z_total = 1/Z1 + 1/Z2 + ..."""
    # TODO: Implement this
    raise NotImplementedError

def voltage_divider(z1: complex, z2: complex, v_in: complex) -> complex:
    """Output voltage across z2: V_out = V_in * Z2 / (Z1 + Z2)."""
    # TODO: Implement this
    raise NotImplementedError

def current_divider(z1: complex, z2: complex, i_total: complex) -> complex:
    """Current through z1 in parallel branch: I1 = I_total * Z2 / (Z1 + Z2)."""
    # TODO: Implement this
    raise NotImplementedError
PYEOF

# circuits/ac_analysis.py
cat > "$PROJECT_DIR/circuits/ac_analysis.py" << 'PYEOF'
import cmath
import math

def apparent_power(v_rms: float, i_rms: float) -> float:
    """S = V_rms * I_rms."""
    return v_rms * i_rms

def resonant_frequency(inductance: float, capacitance: float) -> float:
    """f0 = 1 / (2π√(LC))."""
    # TODO: Implement this
    raise NotImplementedError

def quality_factor(f0: float, bandwidth: float) -> float:
    """Q = f0 / bandwidth."""
    # TODO: Implement this
    raise NotImplementedError

def power_factor(z: complex) -> float:
    """PF = cos(phase_angle(Z)) = R / |Z|."""
    # TODO: Implement this
    raise NotImplementedError

def real_power(v_rms: float, i_rms: float, pf: float) -> float:
    """P = V_rms * I_rms * PF."""
    # TODO: Implement this
    raise NotImplementedError

def reactive_power(v_rms: float, i_rms: float, pf: float) -> float:
    """Q = V_rms * I_rms * sin(arccos(PF))."""
    # TODO: Implement this
    raise NotImplementedError

def impedance_to_polar(z: complex) -> tuple:
    """Convert Z to (magnitude, phase_degrees)."""
    # TODO: Implement this
    raise NotImplementedError
PYEOF

# circuits/analysis.py
cat > "$PROJECT_DIR/circuits/analysis.py" << 'PYEOF'
def thevenin_equivalent(v_oc: complex, i_sc: complex) -> tuple:
    """
    Calculate Thevenin equivalent circuit.
    Returns (V_th, Z_th).
    V_th = V_oc
    Z_th = V_oc / I_sc
    """
    # TODO: Implement this
    raise NotImplementedError

def norton_equivalent(v_oc: complex, i_sc: complex) -> tuple:
    """
    Calculate Norton equivalent circuit.
    Returns (I_n, Z_n).
    I_n = I_sc
    Z_n = V_oc / I_sc
    """
    # TODO: Implement this
    raise NotImplementedError

def max_power_transfer(v_th: complex, z_th: complex) -> float:
    """
    Calculate max average power transfer to a matched load.
    Load Z_L should be conjugate of Z_th.
    P_max = |V_th|^2 / (4 * Re(Z_th)) for DC/Resistive
    P_max = |V_th|^2 / (8 * Re(Z_th)) for AC RMS (standard convention for this lib)
    """
    # TODO: Implement this
    raise NotImplementedError
PYEOF

# --- Create Test Files ---

# tests/conftest.py
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
PYEOF

# tests/test_components.py
cat > "$PROJECT_DIR/tests/test_components.py" << 'PYEOF'
import pytest
import cmath
from circuits.components import Resistor, Capacitor, Inductor

def test_resistor_impedance_is_real():
    r = Resistor(1000)
    z = r.impedance(1000)
    assert z == complex(1000, 0)

def test_capacitor_impedance_at_1khz():
    # Z = 1 / (j * 2*pi * 1000 * 1e-6) = -j * 159.155...
    c = Capacitor(1e-6)
    z = c.impedance(1000)
    assert z.real == pytest.approx(0, abs=1e-9)
    assert z.imag == pytest.approx(-159.154943, rel=1e-5)

def test_inductor_impedance_at_1khz():
    # Z = j * 2*pi * 1000 * 0.01 = j * 62.83...
    l = Inductor(0.01)
    z = l.impedance(1000)
    assert z.real == pytest.approx(0, abs=1e-9)
    assert z.imag == pytest.approx(62.831853, rel=1e-5)

def test_capacitor_impedance_decreases_with_freq():
    c = Capacitor(1e-6)
    z1 = abs(c.impedance(1000))
    z2 = abs(c.impedance(10000))
    assert z2 < z1

def test_inductor_impedance_increases_with_freq():
    l = Inductor(0.01)
    z1 = abs(l.impedance(1000))
    z2 = abs(l.impedance(10000))
    assert z2 > z1
PYEOF

# tests/test_networks.py
cat > "$PROJECT_DIR/tests/test_networks.py" << 'PYEOF'
import pytest
from circuits.networks import series_impedance, parallel_impedance, voltage_divider, current_divider

def test_two_resistors_in_series():
    z_list = [complex(100, 0), complex(200, 0)]
    z_total = series_impedance(z_list)
    assert z_total == complex(300, 0)

def test_two_resistors_in_parallel():
    z_list = [complex(100, 0), complex(200, 0)]
    z_total = parallel_impedance(z_list)
    # 1 / (1/100 + 1/200) = 1 / 0.015 = 66.66...
    assert z_total.real == pytest.approx(66.666667, rel=1e-5)

def test_rc_series_impedance():
    # R=1000, C at -159j
    z_list = [complex(1000, 0), complex(0, -159.15)]
    z_total = series_impedance(z_list)
    assert z_total == complex(1000, -159.15)

def test_rlc_parallel_impedance():
    # Simple check: Z1=100, Z2=100. Parallel should be 50.
    z_list = [complex(100, 0), complex(100, 0)]
    z_total = parallel_impedance(z_list)
    assert z_total == complex(50, 0)

def test_voltage_divider_resistive():
    z1 = complex(1000, 0)
    z2 = complex(2000, 0)
    v_in = complex(10, 0)
    v_out = voltage_divider(z1, z2, v_in)
    # V_out = 10 * 2000 / 3000 = 6.66...
    assert v_out.real == pytest.approx(6.666667, rel=1e-5)

def test_voltage_divider_rc():
    z1 = complex(0, -100) # C
    z2 = complex(100, 0)  # R
    v_in = complex(10, 0)
    # V_out = 10 * 100 / (100 - 100j) = 1000 / (100-100j)
    # = 10 / (1-1j) = 10(1+1j)/2 = 5 + 5j
    v_out = voltage_divider(z1, z2, v_in)
    assert v_out.real == pytest.approx(5.0)
    assert v_out.imag == pytest.approx(5.0)

def test_current_divider_two_resistors():
    # I_total = 3A, R1=100, R2=200. I through R1 (z1)?
    # I1 = 3 * 200 / 300 = 2A
    z1 = complex(100, 0)
    z2 = complex(200, 0)
    i_total = complex(3, 0)
    i1 = current_divider(z1, z2, i_total)
    assert i1.real == pytest.approx(2.0)
PYEOF

# tests/test_ac_analysis.py
cat > "$PROJECT_DIR/tests/test_ac_analysis.py" << 'PYEOF'
import pytest
from circuits.ac_analysis import *

def test_resonant_frequency_lc():
    # f = 1 / (2pi sqrt(10e-3 * 100e-9))
    # LC = 1e-9, sqrt(LC) = 3.162e-5
    # 2pi * sqrt = 1.9869e-4
    # f = 5032.92...
    f0 = resonant_frequency(10e-3, 100e-9)
    assert f0 == pytest.approx(5032.92, rel=1e-4)

def test_quality_factor():
    assert quality_factor(5000, 500) == 10.0

def test_power_factor_resistive():
    assert power_factor(complex(100, 0)) == 1.0

def test_power_factor_inductive():
    # 45 degrees, cos(45) = 0.707...
    assert power_factor(complex(100, 100)) == pytest.approx(0.707106, rel=1e-5)

def test_real_power():
    assert real_power(120, 5, 0.8) == 480.0

def test_reactive_power():
    # PF=0.8 means cos(phi)=0.8, sin(phi)=0.6
    # Q = 120 * 5 * 0.6 = 360
    assert reactive_power(120, 5, 0.8) == pytest.approx(360.0, rel=1e-5)

def test_impedance_to_polar_real():
    mag, phase = impedance_to_polar(complex(100, 0))
    assert mag == 100.0
    assert phase == 0.0

def test_impedance_to_polar_complex():
    mag, phase = impedance_to_polar(complex(100, 100))
    assert mag == pytest.approx(141.421356, rel=1e-5)
    assert phase == 45.0
PYEOF

# tests/test_analysis.py
cat > "$PROJECT_DIR/tests/test_analysis.py" << 'PYEOF'
import pytest
from circuits.analysis import thevenin_equivalent, norton_equivalent, max_power_transfer

def test_thevenin_voltage():
    v, z = thevenin_equivalent(complex(12, 0), complex(0.1, 0))
    assert v == complex(12, 0)

def test_thevenin_impedance():
    v, z = thevenin_equivalent(complex(12, 0), complex(0.1, 0))
    # Z = 12 / 0.1 = 120
    assert z == complex(120, 0)

def test_norton_current():
    i, z = norton_equivalent(complex(12, 0), complex(0.1, 0))
    assert i == complex(0.1, 0)

def test_norton_impedance_equals_thevenin():
    _, z_n = norton_equivalent(complex(10, 0), complex(1, 0))
    _, z_th = thevenin_equivalent(complex(10, 0), complex(1, 0))
    assert z_n == z_th

def test_max_power_transfer():
    # V_th = 10, Z_th = 50.
    # P = 10^2 / (8 * 50) = 100 / 400 = 0.25 (using AC RMS formula convention in docstring)
    p = max_power_transfer(complex(10, 0), complex(50, 0))
    assert p == pytest.approx(0.25)
PYEOF

# requirements.txt
echo "pytest>=7.0" > "$PROJECT_DIR/requirements.txt"

# Store checksums of test files to detect tampering
sha256sum $PROJECT_DIR/tests/*.py > /tmp/test_hashes_initial.txt

# Launch PyCharm
echo "Launching PyCharm..."
source /workspace/scripts/task_utils.sh
setup_pycharm_project "$PROJECT_DIR" "circuit_analyzer"

echo "=== Setup complete ==="