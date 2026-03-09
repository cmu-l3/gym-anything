#!/bin/bash
set -e
echo "=== Setting up analyze_email_headers task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create submission directory
mkdir -p /home/ga/submission
chown ga:ga /home/ga/submission
chmod 755 /home/ga/submission

# Setup ground truth directory (hidden)
mkdir -p /var/lib/app/ground_truth

# Generate a random IP in the TEST-NET-3 range (203.0.113.0/24)
RAND_OCTET=$((1 + $RANDOM % 254))
TARGET_IP="203.0.113.${RAND_OCTET}"
echo "$TARGET_IP" > /var/lib/app/ground_truth/origin_ip.txt
chmod 644 /var/lib/app/ground_truth/origin_ip.txt

echo "Target IP for this session: $TARGET_IP"

# Ensure Admin is logged in via Firefox
# We start Firefox early to ensure it's ready
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Create Mailbox "Executive Support"
MAILBOX_ID=$(ensure_mailbox_exists "Executive Support" "executive@helpdesk.local")
echo "Mailbox ID: $MAILBOX_ID"

# Create Customer "Elias Vance" (The fake CEO)
CUSTOMER_EMAIL="ceo.private@gmail.com" 
CUSTOMER_NAME="Elias Vance"

# Construct Realistic Raw Headers
# Note: We inject the Target IP into X-Originating-IP
# PHP string escaping: single quotes inside the string need to be escaped if we use single quotes for the tinker command
RAW_HEADERS="Return-Path: <$CUSTOMER_EMAIL>
Delivered-To: executive@helpdesk.local
Received: from mail-sor-f41.google.com (mail-sor-f41.google.com. [209.85.220.41])
        by mx.helpdesk.local with SMTPS id u12sor283741
        for <executive@helpdesk.local>; Mon, 03 Mar 2025 09:14:22 -0800 (PST)
X-Originating-IP: [$TARGET_IP]
Authentication-Results: mx.helpdesk.local;
       dkim=pass header.i=@gmail.com header.s=20230601 header.b=Ab3x92;
       spf=pass (google.com: domain of $CUSTOMER_EMAIL designates 209.85.220.41 as permitted sender)
From: \"$CUSTOMER_NAME\" <$CUSTOMER_EMAIL>
To: \"Executive Support\" <executive@helpdesk.local>
Subject: URGENT: Confidential Wire Transfer Request
Date: Mon, 03 Mar 2025 09:14:21 -0800
Message-ID: <CABa+8wX9+JustFakeId$RANDOM@mail.gmail.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=\"UTF-8\"
"

# Create the conversation via ORM and inject headers
echo "Creating conversation with headers..."
fs_tinker "
\$mailbox = \\App\\Mailbox::find($MAILBOX_ID);
\$customer = \\App\\Customer::firstOrCreate(
    ['email' => '$CUSTOMER_EMAIL'],
    ['first_name' => 'Elias', 'last_name' => 'Vance']
);

\$conv = new \\App\\Conversation();
\$conv->type = 1; // Email
\$conv->subject = 'URGENT: Confidential Wire Transfer Request';
\$conv->mailbox_id = \$mailbox->id;
\$conv->status = 1; // Active
\$conv->state = 1; 
\$conv->source_type = 1; // Email
\$conv->customer_id = \$customer->id;
\$conv->customer_email = '$CUSTOMER_EMAIL';
\$conv->save();

\$body = 'Please process the attached invoice immediately. It is for the confidential merger acquisition legal fees. I am currently in a meeting and cannot take calls. Wire instructions are attached.\n\n- Elias';

\$thread = new \\App\\Thread();
\$thread->conversation_id = \$conv->id;
\$thread->type = 2; // Customer Message
\$thread->status = 1;
\$thread->state = 3; // Published
\$thread->body = \$body;
\$thread->headers = '$RAW_HEADERS';
\$thread->customer_id = \$customer->id;
\$thread->created_by_customer_id = \$customer->id;
\$thread->save();

\$conv->preview = substr(\$body, 0, 100);
\$conv->threads_count = 1;
\$conv->save();

// Assign to Unassigned folder
\$folder = \\App\\Folder::where('mailbox_id', \$mailbox->id)->where('type', 1)->first();
if (\$folder) {
    \$conv->folder_id = \$folder->id;
    \$conv->save();
    \$folder->updateCounters();
}
"

# Force cache clear to ensure it shows up
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# Navigate Firefox to the mailbox
wait_for_window "firefox|mozilla|freescout" 60
focus_firefox
navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="