# Changelog

- 2026-10-23 **2.0.2**
    - TLS on port 25 is switched on with `smtpd_tls_security_level = may`, the documented equivalent of the deprecated `smtpd_use_tls = yes`, so the relay behaves as before and postconf no longer warns about the configuration
    - The image builds without a warning of the docker build checks
    - A test checks that postconf prints no warning, in the image and in a started container

- 2026-10-23 **2.0.1**
    - The version line 2 is built and published again as `mwaeckerlin/smtp-relay-tls:2`, for amd64 and arm64, on every push to this branch and every week with the run on master, so it gets the security fixes of its base images
    - A test checks the image: postfix accepts its configuration, the mail system starts, and TLS with the certificate of `MAILHOST` and the `OPENDKIM` milter reach the effective configuration
