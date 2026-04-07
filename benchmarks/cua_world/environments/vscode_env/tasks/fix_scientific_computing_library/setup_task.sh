#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Scientific Computing Library Task ==="

WORKSPACE_DIR="/home/ga/workspace/numlib"
sudo -u ga mkdir -p "$WORKSPACE_DIR/numlib"

# Record task start time
date +%s > /tmp/task_start_time.txt

# ──────────────────────────────────────────────────────────
# 1. numlib/integration.py (BUG: Trapezoidal weights instead of Simpson's)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/numlib/integration.py" << 'EOF'
"""Numerical Integration Module."""

def simpsons_rule(f, a, b, n):
    """
    Integrate f(x) from a to b using Simpson's 1/3 rule with n subintervals.
    """
    if n % 2 != 0:
        n += 1  # n must be even for Simpson's rule
        
    h = (b - a) / n
    x = [a + i * h for i in range(n + 1)]
    y = [f(xi) for xi in x]
    
    # BUG: These are weights for the trapezoidal rule, not Simpson's rule.
    # Simpson's rule weights should follow the pattern: 1, 4, 2, 4, ..., 4, 1
    weights = [1] + [2] * (n - 1) + [1]
    
    integral = (h / 3.0) * sum(w * yi for w, yi in zip(weights, y))
    return integral
EOF

# ──────────────────────────────────────────────────────────
# 2. numlib/ode_solver.py (BUG: k3 uses k1 instead of k2)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/numlib/ode_solver.py" << 'EOF'
"""Ordinary Differential Equation Solver Module."""

def rk4_step(f, t, y, h):
    """
    Perform one step of the classic 4th-order Runge-Kutta method.
    Solves dy/dt = f(t, y).
    """
    k1 = f(t, y)
    k2 = f(t + h / 2.0, y + (h / 2.0) * k1)
    
    # BUG: k3 should evaluate at y + (h/2)*k2, not k1
    k3 = f(t + h / 2.0, y + (h / 2.0) * k1)
    
    k4 = f(t + h, y + h * k3)
    
    return y + (h / 6.0) * (k1 + 2.0 * k2 + 2.0 * k3 + k4)

def solve_ode(f, t0, y0, t_end, h=0.01):
    """Integrate ODE from t0 to t_end."""
    t = t0
    y = y0
    while t < t_end:
        # Prevent overshooting the end time
        if t + h > t_end:
            h = t_end - t
        y = rk4_step(f, t, y, h)
        t += h
    return y
EOF

# ──────────────────────────────────────────────────────────
# 3. numlib/linear_algebra.py (BUG: No partial pivoting)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/numlib/linear_algebra.py" << 'EOF'
"""Linear Algebra Module."""

def lu_solve(A, b):
    """
    Solve the linear system Ax = b using LU decomposition.
    """
    n = len(A)
    U = [row[:] for row in A]
    L = [[1.0 if i == j else 0.0 for j in range(n)] for i in range(n)]
    P = list(range(n))

    for i in range(n):
        # BUG: Missing partial pivoting. Fails if U[i][i] is 0 or very small.
        # Should swap row i with the row having the largest absolute pivot.
        
        if abs(U[i][i]) < 1e-12:
            raise ZeroDivisionError(f"Zero pivot encountered at row {i}")

        for j in range(i + 1, n):
            factor = U[j][i] / U[i][i]
            L[j][i] = factor
            for k in range(i, n):
                U[j][k] -= factor * U[i][k]

    # Forward substitution (L * y = P * b)
    y = [0.0] * n
    for i in range(n):
        y[i] = b[P[i]] - sum(L[i][j] * y[j] for j in range(i))

    # Backward substitution (U * x = y)
    x = [0.0] * n
    for i in range(n - 1, -1, -1):
        x[i] = (y[i] - sum(U[i][j] * x[j] for j in range(i + 1, n))) / U[i][i]

    return x
EOF

# ──────────────────────────────────────────────────────────
# 4. numlib/interpolation.py (BUG: Off-by-one in spline matrix)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/numlib/interpolation.py" << 'EOF'
"""Interpolation Module."""

def cubic_spline_coefficients(x, y):
    """
    Compute natural cubic spline coefficients.
    Returns the second derivatives (M) at the knots.
    """
    n = len(x) - 1
    h = [x[i+1] - x[i] for i in range(n)]
    
    # Construct tridiagonal system for M
    A = [[0.0] * (n + 1) for _ in range(n + 1)]
    B = [0.0] * (n + 1)
    
    # Natural boundary conditions
    A[0][0] = 1.0
    A[n][n] = 1.0
    
    for i in range(1, n):
        # BUG: Off-by-one index. Matrix weights should be h[i-1], 2*(h[i-1]+h[i]), h[i]
        A[i][i-1] = h[i]
        A[i][i] = 2.0 * (h[i] + h[i+1])
        A[i][i+1] = h[i+1]
        
        B[i] = 6.0 * ((y[i+1] - y[i]) / h[i] - (y[i] - y[i-1]) / h[i-1])

    # Solve A * M = B using a simple Gaussian elimination for tridiagonal systems
    M = tridiagonal_solve(A, B)
    return M, h

def tridiagonal_solve(A, b):
    """Solve square linear system (naive dense solver for simplicity)."""
    n = len(A)
    x = [0.0] * n
    # For simplicity of this module, we use a basic solver (assume small n)
    # Note: In production this would be O(N) Thomas algorithm
    from .linear_algebra import lu_solve
    return lu_solve(A, b)

def evaluate_spline(xq, x, y, M, h):
    """Evaluate spline at query points xq."""
    results = []
    for q in xq:
        # Find interval
        for i in range(len(x)-1):
            if x[i] <= q <= x[i+1]:
                break
        
        dx = q - x[i]
        dx_next = x[i+1] - q
        
        val = (M[i] * dx_next**3 + M[i+1] * dx**3) / (6.0 * h[i])
        val += (y[i] - M[i] * h[i]**2 / 6.0) * (dx_next / h[i])
        val += (y[i+1] - M[i+1] * h[i]**2 / 6.0) * (dx / h[i])
        results.append(val)
        
    return results
EOF

# ──────────────────────────────────────────────────────────
# 5. numlib/root_finder.py (BUG: Bisection interval update swapped)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/numlib/root_finder.py" << 'EOF'
"""Root Finding Module."""

def bisection_method(f, a, b, tol=1e-6, max_iter=100):
    """
    Find root of f(x) in interval [a, b] using the Bisection method.
    Requires f(a) and f(b) to have opposite signs.
    """
    fa = f(a)
    fb = f(b)
    
    if fa * fb > 0:
        raise ValueError(f"Function must have opposite signs at interval endpoints. f({a})={fa}, f({b})={fb}")
        
    for _ in range(max_iter):
        mid = (a + b) / 2.0
        fmid = f(mid)
        
        if abs(fmid) < tol or (b - a) / 2.0 < tol:
            return mid
            
        # BUG: The interval update logic is reversed.
        # If f(mid) has the same sign as f(a), the root is in [mid, b], so a = mid.
        if fmid * fa > 0:
            b = mid  # Should be: a = mid
        else:
            a = mid  # Should be: b = mid
            
    return (a + b) / 2.0
EOF

# ──────────────────────────────────────────────────────────
# 6. Test Suite
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/run_tests.py" << 'EOF'
#!/usr/bin/env python3
import math
import sys
import json
import traceback

sys.path.insert(0, ".")
from numlib.integration import simpsons_rule
from numlib.ode_solver import solve_ode
from numlib.linear_algebra import lu_solve
from numlib.interpolation import cubic_spline_coefficients, evaluate_spline
from numlib.root_finder import bisection_method

def run_all_tests():
    report = {
        "integration": {"passed": False, "error": ""},
        "ode_solver": {"passed": False, "error": ""},
        "linear_algebra": {"passed": False, "error": ""},
        "interpolation": {"passed": False, "error": ""},
        "root_finder": {"passed": False, "error": ""}
    }

    # 1. Integration (Integral of sin(x) from 0 to pi is 2.0)
    try:
        val = simpsons_rule(math.sin, 0, math.pi, 1000)
        expected = 2.0
        err = abs(val - expected)
        if err < 1e-6:
            report["integration"]["passed"] = True
        else:
            report["integration"]["error"] = f"Expected {expected}, got {val} (error: {err:e})"
    except Exception as e:
        report["integration"]["error"] = traceback.format_exc()

    # 2. ODE Solver (dy/dt = -y, y(0)=1 => y(5) = e^-5)
    try:
        val = solve_ode(lambda t, y: -y, 0.0, 1.0, 5.0, h=0.01)
        expected = math.exp(-5)
        err = abs(val - expected)
        if err < 1e-8:
            report["ode_solver"]["passed"] = True
        else:
            report["ode_solver"]["error"] = f"Expected {expected}, got {val} (error: {err:e})"
    except Exception as e:
        report["ode_solver"]["error"] = traceback.format_exc()

    # 3. Linear Algebra (Requires pivot swap)
    try:
        A = [[0.0, 2.0, 1.0], 
             [1.0, -2.0, 3.0], 
             [-1.0, 1.0, 2.0]]
        b = [4.0, 5.0, 2.0]
        # Solution should be [1, 1, 2]
        x = lu_solve(A, b)
        err = sum(abs(x[i] - expected) for i, expected in enumerate([1.0, 1.0, 2.0]))
        if err < 1e-10:
            report["linear_algebra"]["passed"] = True
        else:
            report["linear_algebra"]["error"] = f"Expected [1, 1, 2], got {x} (error: {err:e})"
    except Exception as e:
        report["linear_algebra"]["error"] = traceback.format_exc()

    # 4. Interpolation (Runge function fitting)
    try:
        runge = lambda x: 1.0 / (1.0 + 25.0 * x**2)
        x_knots = [i/5.0 - 1.0 for i in range(11)] # -1.0 to 1.0, 11 points
        y_knots = [runge(xi) for xi in x_knots]
        
        M, h = cubic_spline_coefficients(x_knots, y_knots)
        
        # Check midpoint
        test_val = evaluate_spline([0.1], x_knots, y_knots, M, h)[0]
        expected = runge(0.1)
        err = abs(test_val - expected)
        
        if err < 0.05: # Spline should be very accurate here
            report["interpolation"]["passed"] = True
        else:
            report["interpolation"]["error"] = f"Expected {expected} at x=0.1, got {test_val} (error: {err:e})"
    except Exception as e:
        report["interpolation"]["error"] = traceback.format_exc()

    # 5. Root Finder (x^3 - x - 2 = 0 in [1, 2])
    try:
        f = lambda x: x**3 - x - 2
        root = bisection_method(f, 1.0, 2.0, tol=1e-6)
        expected = 1.5213797
        err = abs(root - expected)
        if err < 1e-5:
            report["root_finder"]["passed"] = True
        else:
            report["root_finder"]["error"] = f"Expected {expected}, got {root} (error: {err:e})"
    except Exception as e:
        report["root_finder"]["error"] = traceback.format_exc()

    return report

if __name__ == "__main__":
    report = run_all_tests()
    
    if "--json" in sys.argv:
        json_path = sys.argv[sys.argv.index("--json") + 1]
        with open(json_path, "w") as f:
            json.dump(report, f, indent=2)
    else:
        print("=== Numerical Methods Test Report ===")
        all_passed = True
        for module, res in report.items():
            status = "PASS" if res["passed"] else "FAIL"
            print(f"[{status}] {module}")
            if not res["passed"]:
                all_passed = False
                print(f"       {res['error'].split(chr(10))[-2] if 'Traceback' in res['error'] else res['error']}")
        
        if all_passed:
            print("\nSUCCESS: All tests passed!")
            sys.exit(0)
        else:
            print("\nERROR: Some tests failed.")
            sys.exit(1)
EOF
chmod +x "$WORKSPACE_DIR/run_tests.py"

# Set permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Ensure VS Code is running
echo "Starting VS Code..."
sudo -u ga DISPLAY=:1 code "$WORKSPACE_DIR" &
sleep 5

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code"; then
        DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="