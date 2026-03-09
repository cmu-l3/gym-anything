package com.legacy;

import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Properties;

/**
 * Loads application configuration from a {@code .properties} file on disk.
 *
 * <p>Configuration is critical infrastructure: missing or unreadable config
 * must be treated as a fatal error, not silently defaulted.  If the file
 * cannot be opened or read, the caller must receive an {@link IOException}
 * so it can halt startup or alert an operator.
 */
public class ConfigLoader {

    /**
     * Loads a {@link Properties} object from the given file path.
     *
     * <p>BUG 1 (exception swallowing): any {@link IOException} (file not
     * found, permission denied, disk error) is caught and suppressed.
     * The method returns an empty {@code Properties} object, giving the
     * caller no way to distinguish "successfully loaded an empty file" from
     * "I/O error — nothing was loaded".  Services silently start with
     * default/zero values for all settings.
     *
     * <p>BUG 2 (resource leak): if the call to {@code props.load(is)}
     * throws an unexpected runtime exception, the {@code InputStream is}
     * was already opened but the {@code catch (IOException)} block does not
     * cover that path — {@code is.close()} is never called and the file
     * descriptor leaks.  Use try-with-resources to guarantee closure.
     *
     * <p>Fix: declare {@code load()} to {@code throws IOException} and
     * remove the {@code catch} block, so all I/O failures propagate.  Wrap
     * the stream in a try-with-resources block to prevent descriptor leaks.
     *
     * @param filePath absolute or relative path to the {@code .properties} file
     * @return populated {@link Properties} object
     * @throws IOException if the file cannot be opened or read
     *         <em>(currently suppressed — must be fixed)</em>
     */
    public Properties load(String filePath) {
        Properties props = new Properties();
        try {
            InputStream is = new FileInputStream(filePath);  // BUG: not try-with-resources
            props.load(is);
            // BUG: 'is' is never closed after successful load (missing is.close())
        } catch (IOException e) {
            // BUG: I/O failure swallowed — caller receives empty Properties
            System.err.println("[ConfigLoader] WARNING: could not load config from '"
                               + filePath + "': " + e.getMessage());
        }
        return props;
    }
}
