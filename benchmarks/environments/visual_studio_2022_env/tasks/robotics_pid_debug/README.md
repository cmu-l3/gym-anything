# Task: robotics_pid_debug

## Domain Context

**Primary occupation**: Robotics / Embedded Software Engineers (Medical Devices sector)

The ArmController library drives a 3-DOF robotic surgical arm. During integration testing three distinct hardware failure modes were observed — each traceable to a software bug in a different controller component. This is `very_hard` because:
- The symptoms (oscillation, joint overrun, velocity magnitude error) point to bugs that require domain knowledge of control systems and unit conversion to diagnose
- Each file's code *looks syntactically reasonable* — the bugs are semantically wrong, not obviously broken
- The agent must understand PID controller math, joint limit logic, and mrad/s → rad/s conversion to fix them

## Injected Bugs (Ground Truth)

### Bug 1: PidController.cs — Derivative term sign inverted

**Symptom**: Arm oscillates; control loop diverges instead of converging.

**Code**:
```csharp
// BUGGY (inverted sign → adds energy when converging):
derivative = (_previousError - error) / dt;

// CORRECT (standard discrete PID derivative):
derivative = (error - _previousError) / dt;
```

**Why it matters**: When the arm is converging (error decreasing), `error - previousError` is negative, producing damping. The inverted form `previousError - error` is positive — it adds extra drive, causing the arm to overshoot and oscillate.

### Bug 2: JointLimiter.cs — Clamp condition inverted

**Symptom**: Joint travels past hard stops, triggering hardware fault interrupt.

**Code**:
```csharp
// BUGGY (returns raw value for OUT-OF-RANGE inputs):
if (requestedAngle > MinAngle && requestedAngle < MaxAngle) {
    return Math.Clamp(...); // in-range path — coincidentally correct but this branch handles valid values
} else {
    return requestedAngle;  // BUG: out-of-range values returned unclamped
}

// CORRECT: return Math.Clamp(requestedAngle, MinAngle, MaxAngle); — unconditional
```

### Bug 3: VelocityScaler.cs — Multiply instead of divide

**Symptom**: Motor commands are 1000× too large; arm moves at dangerous speed.

**Code**:
```csharp
// BUGGY (mrad/s × 1000 = 1,000,000× wrong):
return velocityMilliRadPerSec * MilliRadiansPerRadian;  // * 1000

// CORRECT (mrad/s ÷ 1000 = rad/s):
return velocityMilliRadPerSec / MilliRadiansPerRadian;  // / 1000
```

## Success Criteria

| Criterion | Points | Fix detected by |
|-----------|--------|-----------------|
| PID derivative: `error - _previousError` (not inverted) | 35 | Regex on PidController.cs |
| JointLimiter: no bare `return requestedAngle` in out-of-range path | 35 | Regex on JointLimiter.cs |
| VelocityScaler: divide by 1000 (not multiply) | 20 | Regex on VelocityScaler.cs |
| Build: 0 errors | (gate) | dotnet build |

**Pass threshold**: 60 points
**Build gate**: If build has errors, score is capped at 40

## Verification Strategy

`export_result.ps1`:
1. Kills VS to flush edits
2. Reads `PidController.cs`, `JointLimiter.cs`, `VelocityScaler.cs`
3. Checks for bug patterns (inverted sign, bare return, multiply)
4. Checks for fix patterns (correct sign, Math.Clamp, divide)
5. Runs `dotnet build`
6. Writes result JSON to `C:\Users\Docker\robotics_pid_debug_result.json`

`verifier.py`:
1. Copies result JSON + all 3 source files
2. Independent regex analysis per file
3. 35 + 35 + 20 scoring with partial credit for modified-but-unclear
4. Build gate
