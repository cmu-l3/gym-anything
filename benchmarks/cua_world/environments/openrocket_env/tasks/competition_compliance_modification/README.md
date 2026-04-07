# Competition Compliance Modification

## Overview
A TRA safety review has found 4 compliance violations in the competition rocket. The agent must identify all violations, correct each one, verify through simulation, and write a compliance certification memo.

## Domain Context
The Tripoli Rocketry Association (TRA) has strict safety standards for competition rockets. Key requirements include: drogue deployment at apogee, main deployment at or below 244m (800ft) AGL, adequate fin size for stability, and current simulation data verifying safe flight characteristics.

## 4 Injected Violations
1. **Drogue deploy event**: Changed from 'apogee' to 'altitude' (unsafe — drogue must deploy at apogee)
2. **Main deploy altitude**: Set to 500m (must be <=244m / 800ft per TRA rules)
3. **Fin height**: Shrunk to 15mm (causes instability — original was 76mm)
4. **Simulations**: All reset to 'outdated' (no current verification data)

## Source Data
- **Base rocket**: `dual_parachute_deployment.ork` — real dual-deploy high-power rocket design

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Drogue deploy fixed | 22 | Deploy event is 'apogee' |
| Main deploy fixed | 22 | Deploy altitude <= 244m |
| Fins fixed | 21 | Fin height >= 50mm |
| Simulation run | 20 | At least one uptodate simulation |
| Compliance memo | 15 | Meaningful memo documenting fixes |
| **Pass threshold** | **60** | Requires >=3 violations fixed |

## Verification Strategy
Verifier parses `.ork` ZIP+XML to check each violation independently. The memo is checked for existence and relevant keywords (violation references, fix descriptions, multiple items).
