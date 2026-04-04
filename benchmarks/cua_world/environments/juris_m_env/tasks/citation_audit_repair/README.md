# citation_audit_repair

## Overview
A law review editor receives a Juris-M library of 10 SCOTUS cases imported automatically. The import process introduced several citation errors that must be found and fixed.

## Errors Planted (do not include in task description shown to agent)
- Mapp v. Ohio: reporter = "F.3d" (should be "U.S.")
- United States v. Leon: reporter = "F.2d" (should be "U.S.")
- Weeks v. United States: reporter = "F.2d" (should be "U.S.")
- Illinois v. Gates: court = "USDC N.D. Ill." (should be "United States Supreme Court")
- Bivens v. Six Unknown Named Agents: court = "USDC E.D.N.Y." (should be "United States Supreme Court")
- United States v. Cortez: dateDecided = "2001" (should be "1981")
- Terry v. Ohio: firstPage = "999" (should be "1")
- Katz v. United States: firstPage = "999" (should be "347")

## Success Criteria
1. Fix all 3 wrong reporter fields: 20 pts
2. Fix both wrong court fields: 15 pts
3. Fix wrong year on Cortez: 15 pts
4. Fix both wrong first page numbers: 15 pts
5. Add 'audited' tag to >= 8 cases: 20 pts
6. Create 'Audited Cases' collection with >= 8 cases: 15 pts
Pass threshold: 60 points
