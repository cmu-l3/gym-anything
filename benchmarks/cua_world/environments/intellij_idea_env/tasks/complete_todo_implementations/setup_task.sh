#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up complete_todo_implementations task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project configuration
PROJECT_DIR="/home/ga/IdeaProjects/todo-utils"
PKG_DIR="src/main/java/com/example/utils"
TEST_PKG_DIR="src/test/java/com/example/utils"

# Clean previous run
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/$PKG_DIR"
mkdir -p "$PROJECT_DIR/$TEST_PKG_DIR"

# 1. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>todo-utils</artifactId>
    <version>1.0-SNAPSHOT</version>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>
    <dependencies>
        <dependency>
            <groupId>junit</groupId>
            <artifactId>junit</artifactId>
            <version>4.12</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
POMEOF

# 2. Create StringUtils.java (Stubbed)
cat > "$PROJECT_DIR/$PKG_DIR/StringUtils.java" << 'JAVAEOF'
package com.example.utils;

/**
 * Utility class providing common string operations.
 */
public final class StringUtils {

    private StringUtils() {}

    /**
     * Checks if the given string is a palindrome.
     * Ignores case and non-alphanumeric characters.
     * Example: "A man, a plan, a canal: Panama" -> true
     *
     * @param s the string to check, may be null
     * @return true if palindrome, false otherwise (or if null)
     */
    public static boolean isPalindrome(String s) {
        // TODO: Implement this method
        return false;
    }

    /**
     * Counts the number of whitespace-separated words in the string.
     *
     * @param s the string to count words in, may be null
     * @return number of words; 0 if null, empty, or blank
     */
    public static int countWords(String s) {
        // TODO: Implement this method
        return 0;
    }

    /**
     * Reverses the order of words in the given string.
     * Multiple spaces should be collapsed to single spaces.
     *
     * @param s the string to reverse, may be null
     * @return string with words reversed; null if input is null; empty if input is empty
     */
    public static String reverseWords(String s) {
        // TODO: Implement this method
        return null;
    }
}
JAVAEOF

# 3. Create MathUtils.java (Stubbed)
cat > "$PROJECT_DIR/$PKG_DIR/MathUtils.java" << 'JAVAEOF'
package com.example.utils;

/**
 * Utility class providing common mathematical operations.
 */
public final class MathUtils {

    private MathUtils() {}

    /**
     * Computes the greatest common divisor (GCD) using Euclidean algorithm.
     * Negative inputs should be treated as positive.
     * gcd(0, 0) should return 0.
     *
     * @param a first integer
     * @param b second integer
     * @return GCD of |a| and |b|
     */
    public static int gcd(int a, int b) {
        // TODO: Implement this method
        return 0;
    }

    /**
     * Checks if the integer is a prime number.
     *
     * @param n the integer to check
     * @return true if prime, false otherwise
     */
    public static boolean isPrime(int n) {
        // TODO: Implement this method
        return false;
    }

    /**
     * Computes factorial of n (n!).
     *
     * @param n non-negative integer
     * @return n! as long
     * @throws IllegalArgumentException if n < 0
     */
    public static long factorial(int n) {
        // TODO: Implement this method
        return 0;
    }
}
JAVAEOF

# 4. Create StringUtilsTest.java
cat > "$PROJECT_DIR/$TEST_PKG_DIR/StringUtilsTest.java" << 'TESTEOF'
package com.example.utils;
import org.junit.Test;
import static org.junit.Assert.*;

public class StringUtilsTest {
    @Test
    public void testIsPalindrome() {
        assertTrue(StringUtils.isPalindrome("racecar"));
        assertTrue(StringUtils.isPalindrome("A man, a plan, a canal: Panama"));
        assertFalse(StringUtils.isPalindrome("hello"));
        assertFalse(StringUtils.isPalindrome(null));
    }
    @Test
    public void testCountWords() {
        assertEquals(0, StringUtils.countWords(null));
        assertEquals(0, StringUtils.countWords("   "));
        assertEquals(2, StringUtils.countWords("hello world"));
        assertEquals(4, StringUtils.countWords(" one  two   three four "));
    }
    @Test
    public void testReverseWords() {
        assertNull(StringUtils.reverseWords(null));
        assertEquals("", StringUtils.reverseWords(""));
        assertEquals("world hello", StringUtils.reverseWords("hello world"));
        assertEquals("c b a", StringUtils.reverseWords("  a  b   c "));
    }
}
TESTEOF

# 5. Create MathUtilsTest.java
cat > "$PROJECT_DIR/$TEST_PKG_DIR/MathUtilsTest.java" << 'TESTEOF'
package com.example.utils;
import org.junit.Test;
import static org.junit.Assert.*;

public class MathUtilsTest {
    @Test
    public void testGcd() {
        assertEquals(4, MathUtils.gcd(12, 8));
        assertEquals(5, MathUtils.gcd(0, 5));
        assertEquals(4, MathUtils.gcd(-12, 8));
        assertEquals(0, MathUtils.gcd(0, 0));
    }
    @Test
    public void testIsPrime() {
        assertFalse(MathUtils.isPrime(1));
        assertTrue(MathUtils.isPrime(2));
        assertTrue(MathUtils.isPrime(17));
        assertFalse(MathUtils.isPrime(100));
        assertFalse(MathUtils.isPrime(-5));
    }
    @Test
    public void testFactorial() {
        assertEquals(1, MathUtils.factorial(0));
        assertEquals(120, MathUtils.factorial(5));
        assertEquals(3628800, MathUtils.factorial(10));
    }
    @Test(expected = IllegalArgumentException.class)
    public void testFactorialNegative() {
        MathUtils.factorial(-1);
    }
}
TESTEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Record checksums for integrity verification
md5sum "$PROJECT_DIR/$TEST_PKG_DIR/StringUtilsTest.java" > /tmp/initial_test_checksums.txt
md5sum "$PROJECT_DIR/$TEST_PKG_DIR/MathUtilsTest.java" >> /tmp/initial_test_checksums.txt

# Open IntelliJ
setup_intellij_project "$PROJECT_DIR" "todo-utils" 120

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="