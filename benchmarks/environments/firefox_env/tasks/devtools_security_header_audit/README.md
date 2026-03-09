# Task: DevTools Security Header Audit

## Overview

**Difficulty**: Hard
**Occupation**: Software Developers / Web Developers (importance=90, $16.9B GDP)
**Domain**: Web Security / Pre-Deployment Security Assessment

## Background

Web developers routinely benchmark competitor platforms and assess their own security posture using browser developer tools. HTTP security headers (HSTS, CSP, X-Content-Type-Options, X-Frame-Options) are the first line of defense for web applications. A developer auditing these headers before launching their own SaaS platform would inspect top competitor platforms using Firefox DevTools.

## Task Goal

Use Firefox DevTools to inspect HTTP security headers on 5 developer platform websites and produce a structured JSON audit report.

## Target Sites

1. **github.com** - GitHub source code hosting
2. **gitlab.com** - GitLab CI/CD platform
3. **bitbucket.org** - Atlassian code hosting
4. **npmjs.com** - npm package registry
5. **pypi.org** - Python Package Index

## Security Headers to Document

For each site, record the actual values of:
- **Strict-Transport-Security (HSTS)**: How long browsers cache the HTTPS directive (max-age), includeSubdomains/preload settings
- **Content-Security-Policy (CSP)**: Which sources are allowed for scripts, styles, images
- **X-Content-Type-Options**: Whether MIME sniffing is disabled (typically "nosniff")
- **X-Frame-Options**: Whether the site can be embedded in iframes (DENY, SAMEORIGIN, or ALLOW-FROM)

## How to Use Firefox DevTools

1. Press **F12** to open DevTools
2. Click **Network** tab
3. Navigate to the target website (or reload it)
4. Click on the first request (the main HTML document) in the network list
5. Click on **Response Headers** tab on the right panel
6. Note down the header names and their values

## Output Format

`~/Documents/security_audit_report.json` — example structure:
```json
{
  "github.com": {
    "strict-transport-security": "max-age=31536000; includeSubdomains; preload",
    "content-security-policy": "default-src 'none'; ...",
    "x-content-type-options": "nosniff",
    "x-frame-options": "deny"
  },
  "gitlab.com": { ... },
  "bitbucket.org": { ... },
  "npmjs.com": { ... },
  "pypi.org": { ... }
}
```

## Verification Strategy

1. Firefox history contains all 5 domains visited after task start (25 pts)
2. JSON file exists and is valid (15 pts)
3. JSON contains entries for all 5 sites (20 pts)
4. Each site entry has ≥3 non-empty header fields (25 pts)
5. Header values look plausible — HSTS has "max-age", CSP has source directives (15 pts)

**Pass threshold**: 60/100 points

## Anti-Gaming Notes

- JSON file must be created AFTER task start (timestamp check)
- Header values must be actual strings, not booleans or "true"/"false"
- HSTS values must contain "max-age" to be considered valid
- Total non-empty header values across all sites must be ≥10
- Sites not present in JSON get 0 points for that site's criteria
