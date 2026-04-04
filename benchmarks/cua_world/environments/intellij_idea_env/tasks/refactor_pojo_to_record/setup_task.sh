#!/bin/bash
echo "=== Setting up refactor_pojo_to_record task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="banking-events"
PROJECT_DIR="/home/ga/IdeaProjects/$PROJECT_NAME"

# Create project directory structure
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/src/main/java/com/bank/events"
mkdir -p "$PROJECT_DIR/src/main/java/com/bank/service"
mkdir -p "$PROJECT_DIR/src/test/java/com/bank/events"

# 1. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POM'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.bank</groupId>
    <artifactId>banking-events</artifactId>
    <version>1.0-SNAPSHOT</version>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter-api</artifactId>
            <version>5.9.2</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter-engine</artifactId>
            <version>5.9.2</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
POM

# 2. Create the POJO (TransactionEvent.java)
cat > "$PROJECT_DIR/src/main/java/com/bank/events/TransactionEvent.java" << 'JAVA'
package com.bank.events;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

/**
 * Represents a financial transaction event.
 * currently implemented as a standard POJO.
 */
public final class TransactionEvent {
    private final UUID id;
    private final BigDecimal amount;
    private final String currency;
    private final Instant timestamp;

    public TransactionEvent(UUID id, BigDecimal amount, String currency, Instant timestamp) {
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Amount must be positive");
        }
        this.id = id;
        this.amount = amount;
        this.currency = currency;
        this.timestamp = timestamp;
    }

    public UUID getId() {
        return id;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public String getCurrency() {
        return currency;
    }

    public Instant getTimestamp() {
        return timestamp;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        TransactionEvent that = (TransactionEvent) o;
        return Objects.equals(id, that.id) &&
               Objects.equals(amount, that.amount) &&
               Objects.equals(currency, that.currency) &&
               Objects.equals(timestamp, that.timestamp);
    }

    @Override
    public int hashCode() {
        return Objects.hash(id, amount, currency, timestamp);
    }

    @Override
    public String toString() {
        return "TransactionEvent{" +
               "id=" + id +
               ", amount=" + amount +
               ", currency='" + currency + '\'' +
               ", timestamp=" + timestamp +
               '}';
    }
}
JAVA

# 3. Create the Service (AuditService.java) - uses getters
cat > "$PROJECT_DIR/src/main/java/com/bank/service/AuditService.java" << 'JAVA'
package com.bank.service;

import com.bank.events.TransactionEvent;

public class AuditService {

    public String createAuditLog(TransactionEvent event) {
        // This code uses the POJO getters and needs to be refactored
        // to use record accessors (event.amount() instead of event.getAmount())
        return String.format("AUDIT: Transaction %s of %s %s at %s",
                event.getId(),
                event.getAmount(),
                event.getCurrency(),
                event.getTimestamp());
    }
}
JAVA

# 4. Create the Test (TransactionEventTest.java)
cat > "$PROJECT_DIR/src/test/java/com/bank/events/TransactionEventTest.java" << 'JAVA'
package com.bank.events;

import org.junit.jupiter.api.Test;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;

class TransactionEventTest {

    @Test
    void shouldCreateValidEvent() {
        UUID id = UUID.randomUUID();
        BigDecimal amount = new BigDecimal("100.50");
        Instant now = Instant.now();
        
        TransactionEvent event = new TransactionEvent(id, amount, "USD", now);
        
        // These assertions access fields via getters
        assertEquals(id, event.getId());
        assertEquals(amount, event.getAmount());
        assertEquals("USD", event.getCurrency());
        assertEquals(now, event.getTimestamp());
    }

    @Test
    void shouldThrowExceptionForNegativeAmount() {
        assertThrows(IllegalArgumentException.class, () -> {
            new TransactionEvent(UUID.randomUUID(), new BigDecimal("-10.00"), "USD", Instant.now());
        });
    }

    @Test
    void shouldThrowExceptionForZeroAmount() {
        assertThrows(IllegalArgumentException.class, () -> {
            new TransactionEvent(UUID.randomUUID(), BigDecimal.ZERO, "USD", Instant.now());
        });
    }
}
JAVA

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Record initial timestamps for anti-gaming
date +%s > /tmp/task_start_time.txt
stat -c %Y "$PROJECT_DIR/src/main/java/com/bank/events/TransactionEvent.java" > /tmp/initial_file_mtime.txt

# Pre-compile to ensure project is valid initially
echo "Pre-compiling project..."
cd "$PROJECT_DIR"
su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q"

# Launch IntelliJ
setup_intellij_project "$PROJECT_DIR" "banking-events" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="