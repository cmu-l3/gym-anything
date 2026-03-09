package hello;

import org.joda.time.LocaleTime;

public class HelloWorld {
    public static void main(String[] args) {
        LocaleTime currentTime = new LocaleTime();
        System.out.println("The current local time is: " + currentTime);
        Greeter greeter = new Greeter();
        System.out.println(greeter.sayHello());
    }
}
