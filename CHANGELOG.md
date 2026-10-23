# Changelog

- 2026-10-23 **2.0.1**
    - The version line 2 is built and published again as `mwaeckerlin/smtp-relay-tls:2`, for amd64 and arm64, on every push to this branch and every week with the run on master, so it gets the security fixes of its base images
    - A test checks the image: postfix accepts its configuration, the mail system starts, and TLS with the certificate of `MAILHOST` and the `OPENDKIM` milter reach the effective configuration
