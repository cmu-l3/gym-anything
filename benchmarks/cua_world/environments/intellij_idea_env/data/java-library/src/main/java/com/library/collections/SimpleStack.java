package com.library.collections;

import java.util.ArrayList;
import java.util.EmptyStackException;
import java.util.List;

/**
 * A generic stack implementation backed by an ArrayList.
 * Based on standard data-structure patterns (Sedgewick & Wayne, Algorithms 4e).
 *
 * The "collections" component depends on NO other component of this library,
 * making it a natural foundation module in a multi-module Maven build.
 */
public class SimpleStack<T> {

    private final List<T> items = new ArrayList<>();

    /**
     * Pushes an item onto the top of the stack.
     */
    public void push(T item) {
        items.add(item);
    }

    /**
     * Removes and returns the item at the top of the stack.
     *
     * @throws EmptyStackException if the stack is empty
     */
    public T pop() {
        if (isEmpty()) {
            throw new EmptyStackException();
        }
        return items.remove(items.size() - 1);
    }

    /**
     * Returns (without removing) the item at the top of the stack.
     *
     * @throws EmptyStackException if the stack is empty
     */
    public T peek() {
        if (isEmpty()) {
            throw new EmptyStackException();
        }
        return items.get(items.size() - 1);
    }

    /** Returns true if the stack contains no elements. */
    public boolean isEmpty() {
        return items.isEmpty();
    }

    /** Returns the number of elements in the stack. */
    public int size() {
        return items.size();
    }
}
