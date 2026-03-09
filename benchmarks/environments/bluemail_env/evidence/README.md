# BlueMail Environment - Evidence Documentation

## Environment Verification Results

### Installation Script (`install_bluemail.sh`)
- BlueMail binary installed at `/opt/BlueMail/bluemail`
- Dovecot IMAP v2.3.16 installed and running
- Postfix SMTP installed and running
- All dependencies (xdotool, wmctrl, scrot, ffmpeg) installed

### Mail Server Configuration

**Dovecot IMAP** (ports 143 and 993, plain text):
```
● dovecot.service - Dovecot IMAP/POP3 email server
     Active: active (running)
     Status: "v2.3.16 (7e2e900c1a) running"
```

IMAP login test on port 993:
```
* OK [CAPABILITY IMAP4rev1 SASL-IR LOGIN-REFERRALS ID ENABLE IDLE LITERAL+ AUTH=PLAIN AUTH=LOGIN] Dovecot (Ubuntu) ready.
1 OK [...] Logged in
```

IMAP login test on port 143:
```
* OK [CAPABILITY IMAP4rev1 SASL-IR LOGIN-REFERRALS ID ENABLE IDLE LITERAL+ AUTH=PLAIN AUTH=LOGIN] Dovecot (Ubuntu) ready.
1 OK [...] Logged in
```

**Postfix SMTP** (ports 25, 587, 465, plain text):
```
● postfix.service - Postfix Mail Transport Agent
     Active: active (exited)
```

SMTP test on port 587:
```
220 ga-base ESMTP Postfix (Ubuntu)
250-ga-base
250-PIPELINING
```

### Email Data (Real Data - SpamAssassin Public Corpus)

```
Inbox emails: 50 (ham from SpamAssassin corpus)
Junk emails:  20 (spam from SpamAssassin corpus)
Drafts: 0
Sent: 0
```

Sample email subjects:
```
Subject: Re: New Sequences Window
Subject: [SAdev] Interesting approach to Spam handling..
Subject: Re: [SAdev] Live Rule Updates after Release ???
Subject: [ILUG] Re: Problems with RAID1 on cobalt raq3
```

### Wizard Automation

The first-run wizard completes successfully through all 9 steps:
1. Welcome screen -> Continue
2. Add Account -> email + Manual Setup
3. Choose Provider -> Manual Setup
4. Manual Type -> IMAP
5. IMAP Settings (ga@example.com, localhost, Security=None, Port=993)
6. SMTP Settings (localhost, Security=None, Port=587, no sign-in)
7. "Almost done" -> Next
8. "Customize BlueMail" -> Done
9. "Welcome to BlueMail" overlay -> No thanks

### Task Start State Verification

BlueMail shows a clean inbox with:
- 50+ real emails from SpamAssassin corpus visible in email list
- Email preview pane showing full email content
- No dialogs, overlays, or error messages
- Compose button available for email composition tasks

See `06_task_start_state.png` for the verified task start state.

## Screenshots

| File | Description |
|------|-------------|
| `01_smtp_settings_page.png` | SMTP settings page after successful IMAP connection |
| `02_almost_done_page.png` | "You're almost done!" account creation page |
| `03_customize_dialog.png` | "Customize BlueMail" layout selection dialog |
| `04_welcome_overlay.png` | "Welcome to BlueMail" first-run overlay |
| `05_inbox_with_emails.png` | Inbox view with real emails loaded |
| `06_task_start_state.png` | Final task start state - clean inbox ready for agent |

## Process Information

```
/opt/BlueMail/bluemail --no-sandbox  (main process)
/opt/BlueMail/bluemail --type=zygote --no-zygote-sandbox --no-sandbox
/opt/BlueMail/bluemail --type=zygote --no-sandbox
```

Window list:
```
0x00800001  0 ga-base BlueMail
```
