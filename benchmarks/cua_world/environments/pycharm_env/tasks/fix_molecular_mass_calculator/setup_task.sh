#!/bin/bash
echo "=== Setting up fix_molecular_mass_calculator ==="

# Source helper functions
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_molecular_mass_calculator"
PROJECT_DIR="/home/ga/PycharmProjects/chem_mass"

# Clean up any previous run
rm -rf "$PROJECT_DIR"
rm -f /tmp/${TASK_NAME}_start_ts
rm -f /tmp/${TASK_NAME}_result.json

# Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/chem_mass"
su - ga -c "mkdir -p $PROJECT_DIR/tests"

# --- requirements.txt ---
cat > "$PROJECT_DIR/requirements.txt" << 'REQUIREMENTS'
pytest>=7.0
REQUIREMENTS

# --- chem_mass/__init__.py ---
touch "$PROJECT_DIR/chem_mass/__init__.py"

# --- chem_mass/data.py ---
# BUG: Chlorine (Cl) set to 17.0 (atomic number) instead of ~35.45 (atomic mass)
cat > "$PROJECT_DIR/chem_mass/data.py" << 'PYEOF'
# Atomic weights (g/mol) based on IUPAC data
# PERIODIC_TABLE maps symbol to atomic mass

PERIODIC_TABLE = {
    'H': 1.008,
    'He': 4.0026,
    'Li': 6.94,
    'Be': 9.0122,
    'B': 10.81,
    'C': 12.011,
    'N': 14.007,
    'O': 15.999,
    'F': 18.998,
    'Ne': 20.180,
    'Na': 22.990,
    'Mg': 24.305,
    'Al': 26.982,
    'Si': 28.085,
    'P': 30.974,
    'S': 32.06,
    # BUG: Chlorine set to atomic number (17) instead of mass (35.45)
    'Cl': 17.000, 
    'K': 39.098,
    'Ca': 40.078,
    'Fe': 55.845,
    'Cu': 63.546,
    'Zn': 65.38,
    'Br': 79.904,
    'Ag': 107.87,
    'I': 126.90,
    'Pt': 195.08,
    'Au': 196.97,
    'Hg': 200.59,
    'Pb': 207.2
}
PYEOF

# --- chem_mass/calculator.py ---
# BUG 1: Parsing loop only grabs single digit for subscripts (doesn't handle '12' in C12)
# BUG 2: Parentheses logic identifies multiplier but fails to apply it to mass
cat > "$PROJECT_DIR/chem_mass/calculator.py" << 'PYEOF'
import re
from .data import PERIODIC_TABLE

class ChemicalError(Exception):
    pass

class MolarMassCalculator:
    def __init__(self):
        self.atomic_weights = PERIODIC_TABLE

    def calculate(self, formula: str) -> float:
        """
        Parses a chemical formula and returns its molar mass in g/mol.
        Supported formats: H2O, NaCl, C12H22O11, Mg(OH)2
        """
        if not formula:
            return 0.0
            
        return self._parse_group(formula)

    def _parse_group(self, formula_part: str) -> float:
        """
        Recursive parser for chemical groups.
        """
        mass = 0.0
        i = 0
        n = len(formula_part)
        
        while i < n:
            char = formula_part[i]
            
            # Handle Open Parenthesis
            if char == '(':
                # Find matching closing parenthesis
                balance = 1
                j = i + 1
                while j < n and balance > 0:
                    if formula_part[j] == '(':
                        balance += 1
                    elif formula_part[j] == ')':
                        balance -= 1
                    j += 1
                
                if balance != 0:
                    raise ChemicalError("Unbalanced parentheses")
                
                # Recursive call for content inside parens
                inner_content = formula_part[i+1:j-1]
                group_mass = self._parse_group(inner_content)
                
                # Check for subscript after parenthesis
                multiplier = 1
                k = j
                
                # Check for digits after ')'
                num_str = ""
                while k < n and formula_part[k].isdigit():
                    num_str += formula_part[k]
                    k += 1
                
                if num_str:
                    multiplier = int(num_str)
                    i = k  # Advance past number
                else:
                    i = j  # Advance past ')'
                
                # BUG: Logic failure. We calculate group_mass and multiplier,
                # but we just add group_mass without multiplying!
                mass += group_mass 
                continue

            # Handle Elements (Upper case start)
            if char.isupper():
                # Identify element symbol (1 or 2 chars)
                next_char = formula_part[i+1] if i+1 < n else ''
                if next_char.islower():
                    symbol = char + next_char
                    i += 2
                else:
                    symbol = char
                    i += 1
                
                if symbol not in self.atomic_weights:
                    raise ChemicalError(f"Unknown element: {symbol}")
                
                # Handle Subscript
                count = 1
                if i < n and formula_part[i].isdigit():
                    # BUG: This only grabs one digit character!
                    # If formula is C12, it takes '1', sets count=1, and leaves '2' for next loop
                    count = int(formula_part[i])
                    i += 1
                
                mass += self.atomic_weights[symbol] * count
                continue
            
            # If we reach here with a digit that wasn't consumed by element or paren, 
            # it's likely a stray digit resulting from the multi-digit bug
            if char.isdigit():
                 # Just ignore stray digits to suppress immediate crash, but calc will be wrong
                 i += 1
                 continue
                 
            # Skip whitespace or unknown chars
            i += 1
            
        return mass
PYEOF

# --- tests/test_calculator.py ---
cat > "$PROJECT_DIR/tests/test_calculator.py" << 'PYEOF'
import pytest
from chem_mass.calculator import MolarMassCalculator, ChemicalError

@pytest.fixture
def calc():
    return MolarMassCalculator()

def test_simple_elements(calc):
    # Hydrogen: 1.008
    assert calc.calculate("H") == pytest.approx(1.008, 0.001)
    # Oxygen: 15.999
    assert calc.calculate("O") == pytest.approx(15.999, 0.001)

def test_water(calc):
    # H2O = 2*1.008 + 15.999 = 18.015
    assert calc.calculate("H2O") == pytest.approx(18.015, 0.001)

def test_salt_chlorine_bug(calc):
    # NaCl = 22.990 + 35.45 = 58.44
    # Currently fails because Cl is 17.0 in data.py
    assert calc.calculate("NaCl") == pytest.approx(58.44, 0.01)

def test_sucrose_multidigit_bug(calc):
    # C12H22O11 (Sucrose)
    # C: 12.011, H: 1.008, O: 15.999
    # Expected: 12*12.011 + 22*1.008 + 11*15.999 = 342.297
    # Bug: Parses C1 as C, H2 as H, O1 as O. Ignores trailing digits.
    assert calc.calculate("C12H22O11") == pytest.approx(342.297, 0.01)

def test_magnesium_hydroxide_parens_bug(calc):
    # Mg(OH)2
    # Mg: 24.305, O: 15.999, H: 1.008
    # OH group = 17.007
    # Expected: 24.305 + 2 * 17.007 = 58.319
    # Bug: Adds Mg + OH (ignores *2) = 41.312
    assert calc.calculate("Mg(OH)2") == pytest.approx(58.319, 0.01)

def test_calcium_nitrate(calc):
    # Ca(NO3)2
    # Ca: 40.078
    # N: 14.007
    # O3: 3 * 15.999 = 47.997
    # NO3 group: 62.004
    # Total: 40.078 + 2 * 62.004 = 164.086
    assert calc.calculate("Ca(NO3)2") == pytest.approx(164.086, 0.01)
PYEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

# Setup PyCharm Project
setup_pycharm_project "$PROJECT_DIR" "chem_mass"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="