package com.library.collections;

import org.junit.Test;
import java.util.EmptyStackException;
import static org.junit.Assert.*;

public class SimpleStackTest {

    @Test
    public void testPushAndPop() {
        SimpleStack<Integer> stack = new SimpleStack<>();
        stack.push(1);
        stack.push(2);
        stack.push(3);
        assertEquals(Integer.valueOf(3), stack.pop());
        assertEquals(Integer.valueOf(2), stack.pop());
        assertEquals(Integer.valueOf(1), stack.pop());
        assertTrue(stack.isEmpty());
    }

    @Test
    public void testPeek() {
        SimpleStack<String> stack = new SimpleStack<>();
        stack.push("hello");
        assertEquals("hello", stack.peek());
        assertEquals(1, stack.size());  // peek does not remove
    }

    @Test(expected = EmptyStackException.class)
    public void testPopEmptyThrows() {
        new SimpleStack<>().pop();
    }

    @Test
    public void testSize() {
        SimpleStack<Double> stack = new SimpleStack<>();
        assertEquals(0, stack.size());
        stack.push(1.0);
        stack.push(2.0);
        assertEquals(2, stack.size());
    }
}
