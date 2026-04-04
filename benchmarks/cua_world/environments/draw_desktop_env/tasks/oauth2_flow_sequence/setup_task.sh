#!/bin/bash
# Do NOT use set -e

echo "=== Setting up oauth2_flow_sequence task ==="

DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

rm -f /home/ga/Desktop/oauth2_sequence.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/oauth2_sequence.png 2>/dev/null || true

# Create OAuth 2.0 RFC reference document.
# Based on RFC 6749 (OAuth 2.0 Framework) and RFC 7636 (PKCE) — IETF public standards.
# Source: https://datatracker.ietf.org/doc/html/rfc6749 and https://datatracker.ietf.org/doc/html/rfc7636
cat > /home/ga/Desktop/oauth2_rfc_reference.txt << 'RFCEOF'
OAuth 2.0 Authorization Code Flow with PKCE — Sequence Diagram Reference
==========================================================================
Standards: RFC 6749 (OAuth 2.0), RFC 7636 (PKCE), RFC 9068 (JWT Access Tokens)
Context: Single-Page Application (SPA) authenticating via Authorization Code + PKCE
Use Case: Healthcare Portal SPA accessing FHIR R4 Resource Server

PARTICIPANTS (7 lifelines for UML Sequence Diagram)
-----------------------------------------------------
1. End User          — The authenticated human actor
2. Browser/SPA       — JavaScript single-page application (e.g., React)
3. Authorization Server — OAuth 2.0 AS / OIDC Provider (e.g., Auth0, Okta, Azure AD)
4. Token Endpoint    — AS sub-component: /oauth2/token endpoint
5. Resource Server   — Protected FHIR API (e.g., /Patient, /Observation)
6. Session Store     — Redis or localStorage for token state management
7. JWKS Endpoint     — AS public key endpoint: /.well-known/jwks.json

COMPLETE AUTHORIZATION CODE + PKCE FLOW (RFC 6749 §4.1 + RFC 7636)
---------------------------------------------------------------------

Step 1:  End User → Browser/SPA
         Message: "Click Login Button"

Step 2:  Browser/SPA → Browser/SPA  [self-call]
         Message: "generate code_verifier (random 43-128 char string)"
         Note: code_challenge = BASE64URL(SHA256(code_verifier))

Step 3:  Browser/SPA → Authorization Server
         Message: GET /authorize?
           response_type=code
           &client_id=spa_client
           &redirect_uri=https://app.example.com/callback
           &scope=openid profile fhir/Patient.read
           &state=<random CSRF token>
           &code_challenge=<BASE64URL(SHA256(code_verifier))>
           &code_challenge_method=S256

Step 4:  Authorization Server → Browser/SPA
         Message: 302 Redirect to /login page (with state parameter)

Step 5:  End User → Authorization Server
         Message: Submit credentials (username, password / MFA)

Step 6:  Authorization Server → Authorization Server  [self-call]
         Message: Validate credentials, generate authorization code
         Note: code is single-use, expires in 10 minutes, bound to code_challenge

Step 7:  Authorization Server → Browser/SPA
         Message: 302 Redirect to redirect_uri?code=AUTH_CODE&state=CSRF_TOKEN
         [COMBINED FRAGMENT: alt]
           [Valid credentials]:   redirect with authorization code
           [Invalid credentials]: 302 to error page (error=access_denied)

Step 8:  Browser/SPA → Token Endpoint
         Message: POST /token
           grant_type=authorization_code
           &code=AUTH_CODE
           &redirect_uri=https://app.example.com/callback
           &client_id=spa_client
           &code_verifier=<original code_verifier>
           Content-Type: application/x-www-form-urlencoded

Step 9:  Token Endpoint → Token Endpoint  [self-call]
         Message: PKCE Verification: SHA256(code_verifier) == stored code_challenge?
         [COMBINED FRAGMENT: loop / note]
           Verifies: BASE64URL(SHA256(received code_verifier)) matches stored code_challenge

Step 10: Token Endpoint → Browser/SPA
         Message: 200 OK {
           "access_token": "<JWT>",
           "token_type": "Bearer",
           "expires_in": 3600,
           "refresh_token": "<opaque>",
           "id_token": "<JWT>"
         }

Step 11: Browser/SPA → JWKS Endpoint
         Message: GET /.well-known/jwks.json (retrieve public key for JWT verification)

Step 12: JWKS Endpoint → Browser/SPA
         Message: 200 OK { "keys": [ { "kty": "RSA", "kid": "...", "n": "...", "e": "..." } ] }

Step 13: Browser/SPA → Browser/SPA  [self-call]
         Message: Validate ID Token JWT (signature, iss, aud, exp, nonce claims)

Step 14: Browser/SPA → Session Store
         Message: Store { access_token, refresh_token, expiry } in memory / Redis

Step 15: Browser/SPA → Resource Server
         Message: GET /fhir/Patient/123
           Authorization: Bearer <access_token>

Step 16: Resource Server → JWKS Endpoint
         Message: GET /.well-known/jwks.json (introspect / verify token signature)

Step 17: Resource Server → Browser/SPA
         Message: 200 OK { FHIR Patient resource JSON }

--- TOKEN REFRESH FLOW ---
[COMBINED FRAGMENT: opt — Token Expired]

Step 18: Browser/SPA → Browser/SPA  [self-call]
         Message: Detect access_token expiry (check exp claim)

Step 19: Browser/SPA → Token Endpoint
         Message: POST /token  grant_type=refresh_token & refresh_token=<token>

Step 20: Token Endpoint → Browser/SPA
         Message: 200 OK { new access_token, new refresh_token (rotation) }

SECURITY THREATS FOR PAGE 2 — THREAT MODEL
--------------------------------------------
1. Authorization Code Interception Attack
   Risk: Code stolen via malicious redirect_uri or referrer header
   Mitigation: PKCE (RFC 7636) — code_challenge binding

2. Cross-Site Request Forgery (CSRF) on Redirect
   Risk: Attacker forges authorization response
   Mitigation: state parameter with CSRF token (RFC 6749 §10.12)

3. Token Leakage via Browser History / Referrer
   Risk: Access token exposed in URL fragment or Referer header
   Mitigation: Use code flow (not implicit), never put tokens in URLs

4. Refresh Token Theft
   Risk: Long-lived refresh token stolen enables persistent access
   Mitigation: Refresh token rotation, sender-constrained tokens (DPoP)

5. JWT Algorithm Confusion Attack (CVE)
   Risk: Attacker swaps RS256 to HS256, forges token with public key as secret
   Mitigation: Always validate 'alg' header against expected algorithm list

OUTPUT FILES:
  ~/Desktop/oauth2_sequence.drawio   (draw.io source)
  ~/Desktop/oauth2_sequence.png      (PNG export)
RFCEOF

chown ga:ga /home/ga/Desktop/oauth2_rfc_reference.txt 2>/dev/null || true
echo "OAuth2 RFC reference file created: /home/ga/Desktop/oauth2_rfc_reference.txt"

INITIAL_COUNT=$(ls /home/ga/Desktop/*.drawio 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_drawio_count
date +%s > /tmp/task_start_timestamp

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_oauth2.log 2>&1 &"

echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i}s"
        break
    fi
    sleep 1
done

sleep 5
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

DISPLAY=:1 import -window root /tmp/oauth2_start.png 2>/dev/null || true

echo "=== Setup complete: oauth2_rfc_reference.txt on Desktop, draw.io running ==="
