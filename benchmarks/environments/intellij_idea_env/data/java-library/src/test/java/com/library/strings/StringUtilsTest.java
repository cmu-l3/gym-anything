package com.library.strings;

import org.junit.Test;
import static org.junit.Assert.*;

public class StringUtilsTest {

    @Test
    public void testIsBlank() {
        assertTrue(StringUtils.isBlank(null));
        assertTrue(StringUtils.isBlank(""));
        assertTrue(StringUtils.isBlank("   "));
        assertFalse(StringUtils.isBlank("hello"));
    }

    @Test
    public void testReverse() {
        assertEquals("olleh", StringUtils.reverse("hello"));
        assertNull(StringUtils.reverse(null));
    }

    @Test
    public void testIsPalindrome() {
        assertTrue(StringUtils.isPalindrome("racecar"));
        assertTrue(StringUtils.isPalindrome("A man, a plan, a canal: Panama"));
        assertFalse(StringUtils.isPalindrome("hello"));
    }

    @Test
    public void testCountOccurrences() {
        assertEquals(3, StringUtils.countOccurrences("abcabcabc", "abc"));
        assertEquals(0, StringUtils.countOccurrences("hello", "xyz"));
    }

    @Test
    public void testTruncate() {
        assertEquals("Hello...", StringUtils.truncate("Hello World", 8));
        assertEquals("Hi", StringUtils.truncate("Hi", 10));
    }
}
