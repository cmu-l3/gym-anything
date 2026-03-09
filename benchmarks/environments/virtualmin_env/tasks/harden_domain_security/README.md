# Task: Harden Domain Security Configuration

## Overview
A web administrator needs to harden the security posture of acmecorp.test by configuring email authentication (SPF, DKIM), HTTPS enforcement, and Apache security headers. This is a multi-feature task touching DNS, email, and web server configuration.

## Domain Context
Security hardening is a core responsibility for web administrators:
- SPF records prevent email spoofing
- DKIM provides email authentication
- HTTPS redirect protects user data in transit
- Security headers prevent common web attacks
- Disabling directory listing prevents information disclosure

## Goal
Apply 5 independent security hardening measures to acmecorp.test:
1. SPF DNS record
2. DKIM signing enabled
3. HTTP→HTTPS redirect
4. X-Content-Type-Options: nosniff header
5. Disable directory listing

## Why This Is Hard
- Requires using 3+ distinct Virtualmin/Webmin areas: DNS, email config, Apache config
- SPF is a DNS TXT record — requires understanding DNS record types
- DKIM is in Virtualmin's email settings — different section from DNS
- Apache config changes can be made via Virtualmin's web config or Webmin's Apache module
- Agent must discover where each setting lives in the UI
- 5 independent verification criteria

## Edge Cases and Potential Issues
- SPF can be added via Virtualmin's built-in SPF option (`modify-dns --spf`) or manually as a TXT DNS record — both are valid
- DKIM is a **global** Virtualmin setting (`set-dkim --enable`), not per-domain — enabling it affects all domains
- DKIM DNS records may take the form of `default._domainkey` TXT records
- SSL redirect can be done via mod_rewrite rules, Apache `Redirect` directive, or Virtualmin's built-in option — all are accepted
- `X-Content-Type-Options: nosniff` can be in the Apache vhost config OR in `.htaccess` — both locations are checked
- `mod_headers` must be enabled for the nosniff header to work — agent may need to enable it first
- `-Indexes` can be in the vhost config or `.htaccess` — both locations are checked
- The export script checks Apache configs at `/etc/apache2/sites-available/` and `/etc/apache2/sites-enabled/`
- DKIM verification checks three sources: domain info, global config file, and DNS records

## Verification Strategy
- SPF: Check DNS TXT records for "v=spf1"
- DKIM: Check if DKIM is enabled for the domain
- SSL redirect: Check Apache config for redirect rules
- nosniff header: Check Apache config for X-Content-Type-Options
- Indexes: Check Apache config for -Indexes
