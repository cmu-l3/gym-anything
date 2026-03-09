#!/bin/bash
set -e
echo "=== Setting up Extract Superclass task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/eclipse-workspace/notification-system"

# Clean previous attempts
rm -rf "$PROJECT_DIR"
rm -f /tmp/task_result.json

# Create Maven project structure
mkdir -p "$PROJECT_DIR/src/main/java/com/acme/notify"
mkdir -p "$PROJECT_DIR/src/test/java/com/acme/notify"

# Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.acme</groupId>
    <artifactId>notification-system</artifactId>
    <version>1.0.0-SNAPSHOT</version>
    <packaging>jar</packaging>
    <name>Notification System</name>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>
    <dependencies>
        <dependency>
            <groupId>junit</groupId>
            <artifactId>junit</artifactId>
            <version>4.13.2</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
POMEOF

# Create NotificationType enum
cat > "$PROJECT_DIR/src/main/java/com/acme/notify/NotificationType.java" << 'JAVAEOF'
package com.acme.notify;

/**
 * Represents the type of notification channel.
 */
public enum NotificationType {
    EMAIL("Email Notification"),
    SMS("SMS Notification"),
    PUSH("Push Notification"),
    WEBHOOK("Webhook Notification");

    private final String displayName;

    NotificationType(String displayName) {
        this.displayName = displayName;
    }

    public String getDisplayName() {
        return displayName;
    }
}
JAVAEOF

# Create NotificationResult DTO
cat > "$PROJECT_DIR/src/main/java/com/acme/notify/NotificationResult.java" << 'JAVAEOF'
package com.acme.notify;

import java.time.Instant;

/**
 * Immutable result of a notification send attempt.
 */
public class NotificationResult {

    private final boolean success;
    private final String message;
    private final String recipient;
    private final NotificationType type;
    private final Instant timestamp;

    public NotificationResult(boolean success, String message, String recipient, NotificationType type) {
        this.success = success;
        this.message = message;
        this.recipient = recipient;
        this.type = type;
        this.timestamp = Instant.now();
    }

    public boolean isSuccess() {
        return success;
    }

    public String getMessage() {
        return message;
    }

    public String getRecipient() {
        return recipient;
    }

    public NotificationType getType() {
        return type;
    }

    public Instant getTimestamp() {
        return timestamp;
    }

    @Override
    public String toString() {
        return String.format("NotificationResult{success=%s, type=%s, recipient='%s', message='%s'}",
                success, type, recipient, message);
    }
}
JAVAEOF

# Create EmailNotificationService with common + specific code
cat > "$PROJECT_DIR/src/main/java/com/acme/notify/EmailNotificationService.java" << 'JAVAEOF'
package com.acme.notify;

import java.util.ArrayList;
import java.util.List;

/**
 * Service for sending email notifications.
 * Supports HTML and plain text email content.
 */
public class EmailNotificationService {

    // === COMMON FIELDS (shared with SMSNotificationService) ===
    private String serviceName;
    private boolean enabled;
    private int maxRetries;

    // === EMAIL-SPECIFIC FIELDS ===
    private String smtpHost;
    private int smtpPort;
    private String fromAddress;
    private boolean htmlEnabled;
    private final List<String> sentLog = new ArrayList<>();

    public EmailNotificationService(String smtpHost, int smtpPort, String fromAddress) {
        this.serviceName = "EmailService";
        this.enabled = true;
        this.maxRetries = 3;
        this.smtpHost = smtpHost;
        this.smtpPort = smtpPort;
        this.fromAddress = fromAddress;
        this.htmlEnabled = true;
    }

    // === COMMON METHODS (shared with SMSNotificationService) ===

    public boolean isEnabled() {
        return enabled;
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public String getServiceName() {
        return serviceName;
    }

    public int getMaxRetries() {
        return maxRetries;
    }

    public void setMaxRetries(int maxRetries) {
        if (maxRetries < 0) {
            throw new IllegalArgumentException("maxRetries cannot be negative");
        }
        this.maxRetries = maxRetries;
    }

    protected boolean validateRecipient(String recipient) {
        if (recipient == null || recipient.trim().isEmpty()) {
            return false;
        }
        // Basic validation - must contain @ for email-like or digits for phone-like
        return recipient.contains("@") || recipient.matches(".*\\d{3,}.*");
    }

    protected NotificationResult createFailureResult(String reason) {
        return new NotificationResult(false, reason, "", NotificationType.EMAIL);
    }

    // === EMAIL-SPECIFIC METHODS ===

    public String getSmtpHost() {
        return smtpHost;
    }

    public void setSmtpHost(String smtpHost) {
        this.smtpHost = smtpHost;
    }

    public int getSmtpPort() {
        return smtpPort;
    }

    public String getFromAddress() {
        return fromAddress;
    }

    public boolean isHtmlEnabled() {
        return htmlEnabled;
    }

    public void setHtmlEnabled(boolean htmlEnabled) {
        this.htmlEnabled = htmlEnabled;
    }

    public NotificationResult sendEmail(String toAddress, String subject, String body) {
        if (!isEnabled()) {
            return createFailureResult("Email service is disabled");
        }
        if (!validateRecipient(toAddress)) {
            return createFailureResult("Invalid email address: " + toAddress);
        }
        if (subject == null || subject.trim().isEmpty()) {
            return createFailureResult("Email subject cannot be empty");
        }

        // Simulate sending with retries
        for (int attempt = 1; attempt <= getMaxRetries(); attempt++) {
            try {
                // Simulated send logic
                String logEntry = String.format("[%s] Sent to %s: %s", getServiceName(), toAddress, subject);
                sentLog.add(logEntry);
                return new NotificationResult(true, "Email sent successfully", toAddress, NotificationType.EMAIL);
            } catch (Exception e) {
                if (attempt == getMaxRetries()) {
                    return createFailureResult("Failed after " + attempt + " attempts: " + e.getMessage());
                }
            }
        }
        return createFailureResult("Unexpected error in send loop");
    }

    public List<String> getSentLog() {
        return new ArrayList<>(sentLog);
    }

    public void clearSentLog() {
        sentLog.clear();
    }

    public int getSentCount() {
        return sentLog.size();
    }
}
JAVAEOF

# Create SMSNotificationService with common + specific code
cat > "$PROJECT_DIR/src/main/java/com/acme/notify/SMSNotificationService.java" << 'JAVAEOF'
package com.acme.notify;

import java.util.ArrayList;
import java.util.List;

/**
 * Service for sending SMS notifications.
 * Supports text messages with character limit enforcement.
 */
public class SMSNotificationService {

    // === COMMON FIELDS (shared with EmailNotificationService) ===
    private String serviceName;
    private boolean enabled;
    private int maxRetries;

    // === SMS-SPECIFIC FIELDS ===
    private String apiEndpoint;
    private String apiKey;
    private String senderNumber;
    private int maxMessageLength;
    private final List<String> sentLog = new ArrayList<>();

    public SMSNotificationService(String apiEndpoint, String apiKey, String senderNumber) {
        this.serviceName = "SMSService";
        this.enabled = true;
        this.maxRetries = 3;
        this.apiEndpoint = apiEndpoint;
        this.apiKey = apiKey;
        this.senderNumber = senderNumber;
        this.maxMessageLength = 160;
    }

    // === COMMON METHODS (shared with EmailNotificationService) ===

    public boolean isEnabled() {
        return enabled;
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public String getServiceName() {
        return serviceName;
    }

    public int getMaxRetries() {
        return maxRetries;
    }

    public void setMaxRetries(int maxRetries) {
        if (maxRetries < 0) {
            throw new IllegalArgumentException("maxRetries cannot be negative");
        }
        this.maxRetries = maxRetries;
    }

    protected boolean validateRecipient(String recipient) {
        if (recipient == null || recipient.trim().isEmpty()) {
            return false;
        }
        // Basic validation - must contain @ for email-like or digits for phone-like
        return recipient.contains("@") || recipient.matches(".*\\d{3,}.*");
    }

    protected NotificationResult createFailureResult(String reason) {
        return new NotificationResult(false, reason, "", NotificationType.SMS);
    }

    // === SMS-SPECIFIC METHODS ===

    public String getApiEndpoint() {
        return apiEndpoint;
    }

    public String getSenderNumber() {
        return senderNumber;
    }

    public int getMaxMessageLength() {
        return maxMessageLength;
    }

    public void setMaxMessageLength(int maxMessageLength) {
        this.maxMessageLength = maxMessageLength;
    }

    public NotificationResult sendSMS(String phoneNumber, String message) {
        if (!isEnabled()) {
            return createFailureResult("SMS service is disabled");
        }
        if (!validateRecipient(phoneNumber)) {
            return createFailureResult("Invalid phone number: " + phoneNumber);
        }
        if (message == null || message.trim().isEmpty()) {
            return createFailureResult("SMS message cannot be empty");
        }

        // Truncate message if too long
        String finalMessage = message;
        if (message.length() > maxMessageLength) {
            finalMessage = message.substring(0, maxMessageLength - 3) + "...";
        }

        // Simulate sending with retries
        for (int attempt = 1; attempt <= getMaxRetries(); attempt++) {
            try {
                // Simulated send logic
                String logEntry = String.format("[%s] Sent to %s: %s", getServiceName(), phoneNumber, finalMessage);
                sentLog.add(logEntry);
                return new NotificationResult(true, "SMS sent successfully", phoneNumber, NotificationType.SMS);
            } catch (Exception e) {
                if (attempt == getMaxRetries()) {
                    return createFailureResult("Failed after " + attempt + " attempts: " + e.getMessage());
                }
            }
        }
        return createFailureResult("Unexpected error in send loop");
    }

    public List<String> getSentLog() {
        return new ArrayList<>(sentLog);
    }

    public void clearSentLog() {
        sentLog.clear();
    }

    public int getSentCount() {
        return sentLog.size();
    }
}
JAVAEOF

# Create test class
cat > "$PROJECT_DIR/src/test/java/com/acme/notify/NotificationServiceTest.java" << 'JAVAEOF'
package com.acme.notify;

import org.junit.Before;
import org.junit.Test;
import static org.junit.Assert.*;

public class NotificationServiceTest {

    private EmailNotificationService emailService;
    private SMSNotificationService smsService;

    @Before
    public void setUp() {
        emailService = new EmailNotificationService("smtp.example.com", 587, "noreply@acme.com");
        smsService = new SMSNotificationService("https://api.sms.example.com", "test-key", "+15551234567");
    }

    @Test
    public void testEmailServiceDefaults() {
        assertEquals("EmailService", emailService.getServiceName());
        assertTrue(emailService.isEnabled());
        assertEquals(3, emailService.getMaxRetries());
        assertTrue(emailService.isHtmlEnabled());
    }

    @Test
    public void testEmailSendSuccess() {
        NotificationResult result = emailService.sendEmail("user@example.com", "Test Subject", "Hello!");
        assertTrue(result.isSuccess());
        assertEquals("user@example.com", result.getRecipient());
        assertEquals(NotificationType.EMAIL, result.getType());
        assertEquals(1, emailService.getSentCount());
    }

    @Test
    public void testEmailSendWhenDisabled() {
        emailService.setEnabled(false);
        NotificationResult result = emailService.sendEmail("user@example.com", "Test", "Body");
        assertFalse(result.isSuccess());
        assertTrue(result.getMessage().contains("disabled"));
    }

    @Test
    public void testSmsServiceDefaults() {
        assertEquals("SMSService", smsService.getServiceName());
        assertTrue(smsService.isEnabled());
        assertEquals(3, smsService.getMaxRetries());
        assertEquals(160, smsService.getMaxMessageLength());
    }

    @Test
    public void testSmsSendSuccess() {
        NotificationResult result = smsService.sendSMS("+15559876543", "Hello from SMS!");
        assertTrue(result.isSuccess());
        assertEquals("+15559876543", result.getRecipient());
        assertEquals(NotificationType.SMS, result.getType());
        assertEquals(1, smsService.getSentCount());
    }

    @Test
    public void testBothServicesHaveConsistentEnableBehavior() {
        emailService.setEnabled(false);
        smsService.setEnabled(false);
        assertFalse(emailService.isEnabled());
        assertFalse(smsService.isEnabled());
    }
}
JAVAEOF

# Create Eclipse .project and .classpath files to allow direct import
cat > "$PROJECT_DIR/.project" << 'PROJEOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>notification-system</name>
    <comment></comment>
    <projects></projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments></arguments>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.m2e.core.maven2Builder</name>
            <arguments></arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
        <nature>org.eclipse.m2e.core.maven2Nature</nature>
    </natures>
</projectDescription>
PROJEOF

cat > "$PROJECT_DIR/.classpath" << 'CPEOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java">
        <attributes>
            <attribute name="optional" value="true"/>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="src" output="target/test-classes" path="src/test/java">
        <attributes>
            <attribute name="optional" value="true"/>
            <attribute name="maven.pomderived" value="true"/>
            <attribute name="test" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17">
        <attributes>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="con" path="org.eclipse.m2e.MAVEN2_CLASSPATH_CONTAINER">
        <attributes>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="output" path="target/classes"/>
</classpath>
CPEOF

# Create settings prefs
mkdir -p "$PROJECT_DIR/.settings"
cat > "$PROJECT_DIR/.settings/org.eclipse.jdt.core.prefs" << 'SETTEOF'
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.problem.assertIdentifier=error
org.eclipse.jdt.core.compiler.problem.enumIdentifier=error
org.eclipse.jdt.core.compiler.release=enabled
org.eclipse.jdt.core.compiler.source=17
SETTEOF

chown -R ga:ga "$PROJECT_DIR"

# Wait for Eclipse and prepare UI
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
focus_eclipse_window
dismiss_dialogs 3
close_welcome_tab

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="