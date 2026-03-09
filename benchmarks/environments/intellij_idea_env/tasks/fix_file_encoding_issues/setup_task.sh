#!/bin/bash
set -e
echo "=== Setting up Fix File Encoding Task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="legacy-finance-app"
PROJECT_DIR="/home/ga/IdeaProjects/$PROJECT_NAME"

# Clean up previous runs
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java/com/legacy/finance"
mkdir -p "$PROJECT_DIR/src/test/java/com/legacy/finance"

# 1. Create POM
cat > "$PROJECT_DIR/pom.xml" <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.legacy.finance</groupId>
  <artifactId>legacy-finance-app</artifactId>
  <packaging>jar</packaging>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
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
EOF

# 2. Create the BROKEN Java File (UTF-8 first)
cat > "/tmp/CurrencyConfig_utf8.java" <<EOF
package com.legacy.finance;

import java.util.HashMap;
import java.util.Map;

public class CurrencyConfig {
    private static final Map<String, String> SYMBOLS = new HashMap<>();

    static {
        SYMBOLS.put("USD", "$");
        SYMBOLS.put("EUR", "€"); // Euro
        SYMBOLS.put("GBP", "£"); // Pound
        SYMBOLS.put("JPY", "¥"); // Yen
    }

    public static String getSymbol(String currencyCode) {
        return SYMBOLS.getOrDefault(currencyCode, "?");
    }
}
EOF

# Convert to Windows-1252 (ISO-8859-15/Windows-1252 are similar, 1252 has Euro at 0x80)
# We use CP1252 explicitly.
echo "Encoding file to Windows-1252..."
iconv -f UTF-8 -t WINDOWS-1252 "/tmp/CurrencyConfig_utf8.java" > "$PROJECT_DIR/src/main/java/com/legacy/finance/CurrencyConfig.java"

# 3. Create the Test File (Correct UTF-8)
cat > "$PROJECT_DIR/src/test/java/com/legacy/finance/CurrencyTest.java" <<EOF
package com.legacy.finance;

import org.junit.Test;
import static org.junit.Assert.assertEquals;

public class CurrencyTest {
    @Test
    public void testCurrencySymbols() {
        assertEquals("$", CurrencyConfig.getSymbol("USD"));
        assertEquals("€", CurrencyConfig.getSymbol("EUR"));
        assertEquals("£", CurrencyConfig.getSymbol("GBP"));
        assertEquals("¥", CurrencyConfig.getSymbol("JPY"));
    }
}
EOF

# 4. Corrupt Line Endings (Make them CRLF - Windows style)
# Install unix2dos if not present, or use sed
if command -v unix2dos &> /dev/null; then
    find "$PROJECT_DIR" -name "*.java" -exec unix2dos {} \;
else
    sed -i 's/$/\r/' "$PROJECT_DIR/src/main/java/com/legacy/finance/CurrencyConfig.java"
    sed -i 's/$/\r/' "$PROJECT_DIR/src/test/java/com/legacy/finance/CurrencyTest.java"
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# 5. Configure IntelliJ to force UTF-8 (so it misreads the 1252 file)
# We deliberately do NOT set the encoding for this specific file, so it falls back to Project Encoding (UTF-8)
IDEA_CONFIG_DIR="/home/ga/.config/JetBrains/IdeaIC2024.3"
mkdir -p "$IDEA_CONFIG_DIR/options"

# Ensure global encoding is UTF-8
cat > "$IDEA_CONFIG_DIR/options/encoding.xml" <<EOF
<application>
  <component name="Encoding">
    <file url="PROJECT" charset="UTF-8" />
  </component>
</application>
EOF
chown -R ga:ga "$IDEA_CONFIG_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Initial Checksum (of the broken file)
md5sum "$PROJECT_DIR/src/main/java/com/legacy/finance/CurrencyConfig.java" > /tmp/initial_broken_checksum.txt

# Open Project
setup_intellij_project "$PROJECT_DIR" "legacy-finance-app" 120

# Open the specific file so the agent sees it immediately
su - ga -c "DISPLAY=:1 /usr/local/bin/idea --line 10 \"$PROJECT_DIR/src/main/java/com/legacy/finance/CurrencyConfig.java\" > /dev/null 2>&1 &"

sleep 5
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="