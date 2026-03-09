<#
  setup_task.ps1 - ArmController robotics PID debug task
  Creates a .NET 8 library with 3 injected subtle domain-specific bugs.
  Agent must identify and fix all three bugs from robotics domain knowledge.
#>

. "C:\workspace\scripts\task_utils.ps1"

$ProjectDir = "C:\Users\Docker\source\repos\ArmController"
$SlnFile    = "$ProjectDir\ArmController.sln"

Write-Host "=== Setting up robotics_pid_debug task ==="

# ── 1. Clean prior run ────────────────────────────────────────────────────────
Kill-AllVS2022
Start-Sleep -Seconds 2

if (Test-Path $ProjectDir) {
    Remove-Item $ProjectDir -Recurse -Force
}
New-Item -ItemType Directory -Path $ProjectDir -Force | Out-Null

# ── 2. Project file ───────────────────────────────────────────────────────────
@'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>disable</ImplicitUsings>
    <RootNamespace>ArmController</RootNamespace>
    <AssemblyName>ArmController</AssemblyName>
  </PropertyGroup>
</Project>
'@ | Set-Content "$ProjectDir\ArmController.csproj" -Encoding UTF8

# ── 3. PidController.cs — BUG: derivative term sign is inverted ───────────────
# Correct formula: derivative = (previousError - error) / dt  [negative when converging]
# Injected bug:    derivative = (error - previousError) / dt  [positive when converging = positive feedback]
@'
using System;

namespace ArmController
{
    /// <summary>
    /// Discrete PID controller for joint position control.
    /// Computes a torque command given position error.
    ///
    /// Standard PID:
    ///   output = Kp*e + Ki*integral(e) + Kd*de/dt
    ///
    /// where de/dt should be negative when the system is converging
    /// (error shrinking), producing a stabilizing derivative term.
    /// </summary>
    public class PidController
    {
        public double Kp { get; }
        public double Ki { get; }
        public double Kd { get; }

        private double _integral     = 0.0;
        private double _previousError = 0.0;
        private bool   _firstUpdate  = true;

        public PidController(double kp, double ki, double kd)
        {
            Kp = kp;
            Ki = ki;
            Kd = kd;
        }

        /// <summary>
        /// Compute PID output torque command.
        /// </summary>
        /// <param name="setpoint">Desired joint angle (radians)</param>
        /// <param name="measured">Measured joint angle (radians)</param>
        /// <param name="dt">Time step (seconds)</param>
        /// <returns>Torque command (N·m)</returns>
        public double Compute(double setpoint, double measured, double dt)
        {
            if (dt <= 0.0)
                throw new ArgumentException("dt must be positive", nameof(dt));

            double error = setpoint - measured;

            _integral += error * dt;

            double derivative = 0.0;
            if (!_firstUpdate)
            {
                // BUG: sign is inverted — should be (_previousError - error) / dt
                // With (error - _previousError): when error is shrinking, this is negative,
                // which means Kd*derivative is NEGATIVE, REDUCING the output — wait, actually
                // let's think carefully:
                // If setpoint=1, measured goes 0->0.5 (converging):
                //   error goes 1->0.5, so error-prevError = 0.5-1 = -0.5 (negative) -> reduces output OK
                // Actually the classic form uses error - prevError. The correct derivative for
                // STABILIZATION in continuous form is d(error)/dt = (error_new - error_old)/dt.
                // The BUG we inject: we use (previousError - error) instead of (error - previousError).
                // This means when the arm IS converging (error decreasing), the derivative term
                // adds EXTRA drive instead of damping — causing oscillation.
                derivative = (_previousError - error) / dt;
            }

            _previousError = error;
            _firstUpdate   = false;

            return Kp * error + Ki * _integral + Kd * derivative;
        }

        public void Reset()
        {
            _integral      = 0.0;
            _previousError = 0.0;
            _firstUpdate   = true;
        }
    }
}
'@ | Set-Content "$ProjectDir\PidController.cs" -Encoding UTF8

# ── 4. JointLimiter.cs — BUG: condition is inverted (clamps when OUTSIDE, passes when INSIDE) ──
@'
using System;

namespace ArmController
{
    /// <summary>
    /// Hardware joint limiter — clamps joint angle commands to the safe operating range.
    /// Prevents driving a joint past its mechanical hard stops.
    ///
    /// Correct behaviour: if value is outside [minAngle, maxAngle], clamp to the nearest limit.
    /// </summary>
    public class JointLimiter
    {
        public double MinAngle { get; }  // radians
        public double MaxAngle { get; }  // radians

        public JointLimiter(double minAngle, double maxAngle)
        {
            if (minAngle >= maxAngle)
                throw new ArgumentException("minAngle must be less than maxAngle");
            MinAngle = minAngle;
            MaxAngle = maxAngle;
        }

        /// <summary>
        /// Clamp the requested joint angle to the safe range [MinAngle, MaxAngle].
        /// </summary>
        /// <param name="requestedAngle">Requested angle in radians</param>
        /// <returns>Safe, clamped angle in radians</returns>
        public double Clamp(double requestedAngle)
        {
            // BUG: condition is inverted — should be < MinAngle and > MaxAngle
            // As written, this PASSES values outside the limits unchanged and
            // CLAMPS values that are already inside the safe range to the limits.
            if (requestedAngle > MinAngle && requestedAngle < MaxAngle)
            {
                // This path is taken for VALID values — wrongly clamping them
                return Math.Clamp(requestedAngle, MinAngle, MaxAngle);
                // (coincidentally returns the same value since it's already in range,
                // so this path actually does the right thing — it's the ELSE that is wrong)
            }
            else
            {
                // This path is taken for OUT-OF-RANGE values — returning them unchanged
                return requestedAngle;  // BUG: should clamp here, not return raw value
            }
        }

        public bool IsWithinLimits(double angle) =>
            angle >= MinAngle && angle <= MaxAngle;
    }
}
'@ | Set-Content "$ProjectDir\JointLimiter.cs" -Encoding UTF8

# ── 5. VelocityScaler.cs — BUG: multiplies by 1000 instead of dividing ────────
@'
using System;

namespace ArmController
{
    /// <summary>
    /// Converts velocity commands from the trajectory planner (in milli-radians/second)
    /// to the motor driver input format (radians/second).
    ///
    /// The trajectory planner works in milli-radians/second for precision.
    /// The motor driver firmware expects radians/second.
    /// Conversion: rad/s = mrad/s / 1000
    /// </summary>
    public class VelocityScaler
    {
        private const double MilliRadiansPerRadian = 1000.0;

        /// <summary>
        /// Convert a velocity from milli-radians/second to radians/second.
        /// </summary>
        /// <param name="velocityMilliRadPerSec">Velocity in milli-radians per second</param>
        /// <returns>Velocity in radians per second for motor driver</returns>
        public double ToMotorDriverUnits(double velocityMilliRadPerSec)
        {
            // BUG: should DIVIDE by 1000 (mrad/s -> rad/s), not multiply
            // Multiplying causes commands 1000x too large
            return velocityMilliRadPerSec * MilliRadiansPerRadian;
        }

        /// <summary>
        /// Convert a velocity from radians/second back to milli-radians/second.
        /// </summary>
        public double FromMotorDriverUnits(double velocityRadPerSec)
        {
            return velocityRadPerSec * MilliRadiansPerRadian;
        }
    }
}
'@ | Set-Content "$ProjectDir\VelocityScaler.cs" -Encoding UTF8

# ── 6. ArmController facade ────────────────────────────────────────────────────
@'
using System.Collections.Generic;

namespace ArmController
{
    /// <summary>
    /// High-level controller for a 3-DOF robotic surgical arm.
    /// Coordinates PID, joint limiting, and velocity scaling.
    /// </summary>
    public class RobotArmController
    {
        private readonly PidController[]  _pids;
        private readonly JointLimiter[]   _limiters;
        private readonly VelocityScaler   _scaler;
        private const int NumJoints = 3;

        public RobotArmController(
            IEnumerable<(double Kp, double Ki, double Kd)> pidGains,
            IEnumerable<(double Min, double Max)>          jointLimits)
        {
            _pids     = new PidController[NumJoints];
            _limiters = new JointLimiter[NumJoints];
            _scaler   = new VelocityScaler();

            int i = 0;
            foreach (var (kp, ki, kd) in pidGains)
                _pids[i++] = new PidController(kp, ki, kd);

            i = 0;
            foreach (var (min, max) in jointLimits)
                _limiters[i++] = new JointLimiter(min, max);
        }

        /// <summary>
        /// Compute safe torque commands for all joints given setpoints and measurements.
        /// </summary>
        public double[] ComputeTorques(double[] setpoints, double[] measured, double dt)
        {
            var torques = new double[NumJoints];
            for (int j = 0; j < NumJoints; j++)
            {
                double safeSp = _limiters[j].Clamp(setpoints[j]);
                torques[j]    = _pids[j].Compute(safeSp, measured[j], dt);
            }
            return torques;
        }

        /// <summary>
        /// Scale a planner velocity command to motor driver units.
        /// </summary>
        public double ScaleVelocity(double plannerVelocityMradPerSec) =>
            _scaler.ToMotorDriverUnits(plannerVelocityMradPerSec);

        public void ResetAll()
        {
            foreach (var pid in _pids) pid.Reset();
        }
    }
}
'@ | Set-Content "$ProjectDir\RobotArmController.cs" -Encoding UTF8

# ── 7. Build to confirm buggy code compiles ───────────────────────────────────
$dotnet = Find-DotnetExe
Write-Host "Building buggy project to confirm it compiles..."
& $dotnet build "$ProjectDir\ArmController.csproj" --configuration Release 2>&1 | Write-Host

# ── 8. Create solution ────────────────────────────────────────────────────────
Push-Location $ProjectDir
& $dotnet new sln --name ArmController --force 2>&1 | Out-Null
& $dotnet sln add "$ProjectDir\ArmController.csproj" 2>&1 | Out-Null
Pop-Location

# ── 9. Record task-start timestamp ────────────────────────────────────────────
Start-Sleep -Seconds 2
$taskStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$taskStart | Set-Content "C:\Users\Docker\robotics_pid_debug_start_ts.txt" -Encoding UTF8

Write-Host "Task start timestamp: $taskStart"

# ── 10. Launch VS 2022 ────────────────────────────────────────────────────────
Write-Host "Launching Visual Studio 2022..."
$devenvExe = Find-VS2022Exe
Launch-VS2022Interactive -DevenvExe $devenvExe -SolutionPath $SlnFile -WaitSeconds 25

Write-Host "Dismissing first-run VS dialogs..."
try { Dismiss-VSDialogsBestEffort -Retries 3 -InitialWaitSeconds 5 -BetweenRetriesSeconds 2 }
catch { Write-Host "WARNING: Dialog dismissal: $($_.Exception.Message)" }

Write-Host "=== robotics_pid_debug setup complete ==="
