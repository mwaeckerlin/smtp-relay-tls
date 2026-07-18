# Changelog

- 2026-07-18 **headless image**
    - The image no longer contains a shell, busybox or a package
      manager: a compiled `init` binary configures postfix from the
      environment and starts the postfix master daemon directly. The
      behaviour (TLS relay with the certificate from
      `/etc/letsencrypt/live/$MAILHOST/`, optional `OPENDKIM` milter)
      is unchanged.
    - New `init --healthcheck` probe for Docker healthchecks.
    - Delivery-affecting limits are now configurable with high
      defaults: `MESSAGE_SIZE_LIMIT` (default 100 GiB, was postfix's
      10 MB default) and `SMTP_HARD_ERROR_LIMIT` (default 20) — a
      legitimate mail is never bounced by an artificial default.
    - The unused `DAYS` environment variable is gone — the image never
      generated its own certificate; it always expected one in the
      `letsencrypt` volume.
    - New `DISABLE_DNSBL` switch (default off) strips the DNS-blocklist
      lookups from the smtpd restrictions — for test/offline stacks
      whose resolver cannot answer the blocklist zones.
    - The mail queue (`/var/spool/postfix`) is now a declared volume:
      an accepted mail (`250 Ok`) is the server's responsibility and
      the sender never retries — a deferred mail must survive container
      recreates and image updates. Map it to a named volume in
      production.
