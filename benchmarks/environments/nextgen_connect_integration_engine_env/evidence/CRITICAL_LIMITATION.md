# CRITICAL LIMITATIONS - NextGen Connect Environment

**Status**: DOCUMENTED (2026-02-12)

---

## 1. Web Dashboard is MONITORING ONLY

The NextGen Connect 4.5.0 web dashboard at `https://localhost:8443` provides only monitoring capabilities (Dashboard Statistics page showing channel status, message counts). It CANNOT create, edit, or manage channels.

**Impact**: All channel management must be done via the REST API using curl with XML payloads.

## 2. REST API Requires X-Requested-With Header

All REST API calls require the `X-Requested-With: OpenAPI` header. Without it, the server returns HTTP 400.

```bash
# Correct
curl -sk -H "X-Requested-With: OpenAPI" https://localhost:8443/api/server/version

# Wrong (returns 400)
curl -sk https://localhost:8443/api/server/version
```

## 3. Channel XML Requires responseTransformer

Channel XML MUST include a `<responseTransformer>` element in every destination connector. Without it, deployment fails with:

```
NullPointerException: Cannot invoke
"com.mirth.connect.model.Transformer.getInboundDataType()"
because the return value of
"com.mirth.connect.model.Connector.getResponseTransformer()" is null
```

The API returns HTTP 204 (success) even when deployment fails internally. Only the server logs show the error.

## 4. Java WebStart Does Not Work

Java WebStart (icedtea-netx) fails with log4j2 classloader incompatibility:

```
NoClassDefFoundError: Could not initialize class
org.apache.logging.log4j.util.PropertiesUtil
```

The desktop Administrator application cannot be launched via JNLP/javaws on Java 11+.

## 5. SSL Self-Signed Certificate

The web dashboard uses a self-signed SSL certificate. Firefox shows a security warning that requires manual acceptance (Advanced -> Accept the Risk and Continue).

## 6. Output Files in Docker Container

Channel output files (File Writer destinations) are created inside the Docker container filesystem, NOT the host VM filesystem. Use `docker exec nextgen-connect ls /path/` to check outputs.
