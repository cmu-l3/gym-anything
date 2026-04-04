package com.example.demo;

/**
 * Main entry point for the demo application.
 */
public class Main {
    public static void main(String[] args) {
        OldClassName obj = new OldClassName();
        obj.printMessage();

        OldClassName custom = new OldClassName("Custom message");
        System.out.println(custom.getMessage());
    }
}
