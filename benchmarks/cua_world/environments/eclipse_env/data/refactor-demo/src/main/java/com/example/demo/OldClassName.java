package com.example.demo;

/**
 * A simple demo class with message functionality.
 */
public class OldClassName {
    private String message;

    public OldClassName() {
        this.message = "Hello from OldClassName";
    }

    public OldClassName(String message) {
        this.message = message;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }

    public void printMessage() {
        System.out.println(message);
    }
}
