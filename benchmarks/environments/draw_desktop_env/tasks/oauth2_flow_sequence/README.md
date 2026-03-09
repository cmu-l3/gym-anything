# oauth2_flow_sequence — OAuth 2.0 + PKCE UML Sequence Diagram

## Domain Context

**Occupation**: Information Security Engineer ($484M GDP occupation for diagramming tools)

Information Security Engineers create formal UML sequence diagrams as part of compliance documentation, architecture review, and threat modeling. OAuth 2.0 with PKCE (Proof Key for Code Exchange, RFC 7636) is the current recommended flow for public clients (SPAs, mobile apps) and is required by OAuth 2.1, FAPI 2.0 (Financial-grade API), and many compliance frameworks (SOC 2, ISO 27001).

Documenting the exact message sequence — including JWT validation against JWKS, session store interactions, and token refresh — is a standard deliverable in security audits and API governance reviews.

## Task Description

An Information Security Engineer must create a formal UML sequence diagram of the OAuth 2.0 Authorization Code Flow with PKCE for a Single-Page Application, for a compliance audit. The RFC reference document is at `~/Desktop/oauth2_rfc_reference.txt`.

**End state**: A multi-page draw.io diagram (`~/Desktop/oauth2_sequence.drawio`) and a PNG export (`~/Desktop/oauth2_sequence.png`) that contain:
- 7 UML lifelines: End User, Browser/SPA, Authorization Server, Token Endpoint, Resource Server, Session Store, JWKS Endpoint
- ≥18 labeled message arrows covering the complete PKCE flow (code_verifier generation through token usage)
- UML combined fragments: `alt` (credentials valid/invalid), `opt` (token refresh), `loop` or `note` for PKCE check
- Proper UML notation: activation boxes, dashed return arrows, self-calls
- A second page "Threat Model" with 5 security threats as a table (PKCE bypass, CSRF, token leakage, etc.)

## Why This Is Hard

- UML sequence diagrams require specialized shape types in draw.io (lifelines, activation boxes, combined fragments) that are distinct from general flowchart shapes
- 7 participants must be drawn as proper lifeline shapes with correct vertical placement
- 18+ messages require understanding the exact OAuth 2.0 + PKCE handshake sequence from RFC 6749 and RFC 7636
- Combined fragments (`alt`, `opt`) are a specific UML notation requiring container shapes with operand labels
- JWT/JWKS validation involves an additional service-to-service call (Resource Server → JWKS Endpoint) that many implementations omit
- The Threat Model page requires security domain knowledge to produce a credible table (not just placeholder text)

## Success Criteria

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| File saved after task start | 10 | Required (early exit if missing) |
| ≥20 total shapes | 15 | Partial: 6+ shapes = 6 pts |
| ≥15 total edges (messages) | 15 | Partial: 6+ edges = 6 pts |
| ≥5 participant lifelines detected | 20 | Partial: 3+ = 8 pts, any lifeline = 3 pts |
| ≥7 OAuth-specific keywords | 15 | Partial: 3+ keywords = 6 pts, 1+ = 2 pts |
| Combined fragments present | 10 | — |
| ≥2 diagram pages | 10 | — |
| PNG exported | 5 | — |
| **Total** | **100** | **Pass: ≥60** |

## Verification Strategy

The verifier (`verify_oauth2_flow_sequence`):
1. Reads `/tmp/task_result.json` from `export_result.sh`
2. Checks file existence and modification timestamp
3. Detects lifeline shapes via `shape=uml.lifeline` or `shape=table` styles and matches participant categories (user, browser/spa, authserver/authorization, token, resource, jwks, session)
4. Counts OAuth-specific keywords in shape text: `code_verifier`, `code_challenge`, `pkce`, `access_token`, `refresh_token`, `authorization_code`, `bearer`, `jwk`, `id_token`
5. Detects combined fragments via `shape=uml.frame` or container shapes with alt/opt/loop labels
6. Counts total shapes, edges, pages, and PNG file

## Data Source

Based on RFC 6749 (OAuth 2.0 Authorization Framework), RFC 7636 (PKCE), RFC 7519 (JWT), and IETF OAuth Security Best Current Practice (BCP). The 20-step flow in the reference document reflects actual OAuth 2.0 + PKCE implementations in Auth0, Okta, and AWS Cognito.

**Key PKCE-specific steps to capture**:
1. Client generates `code_verifier` (random 43-128 char string)
2. Client computes `code_challenge = BASE64URL(SHA256(code_verifier))`
3. Authorization Request includes `code_challenge` and `code_challenge_method=S256`
4. Token Request includes `code_verifier`
5. Token Endpoint verifies `SHA256(code_verifier) == code_challenge`

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task specification, metadata, scoring hook |
| `setup_task.sh` | Creates `~/Desktop/oauth2_rfc_reference.txt` with RFC-based spec, records start timestamp, launches draw.io blank |
| `export_result.sh` | Parses draw.io XML for lifeline styles, OAuth keywords, fragment shapes, page count, PNG |
| `verifier.py` | Multi-criterion scoring function `verify_oauth2_flow_sequence` |

## Edge Cases

- UML lifelines in draw.io can be created from the UML shape library OR as plain table shapes with a label — verifier accepts both representations
- Combined fragments may be implemented as colored rectangles with text labels instead of proper UML frame shapes — verifier checks for both `shape=uml.frame` and containers with alt/opt/loop label text
- Agent may draw a 5-participant subset (omitting Session Store and JWKS Endpoint) — this scores partial credit on participant criterion but misses some edge count
- Message labels may use abbreviations (AT, RT, ID) instead of full terms — verifier checks for partial keyword matches
