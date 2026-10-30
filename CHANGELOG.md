# Changelog

- 2026-10-30 **3.5.5**
    - The README and the start-up code say what was measured about the Spamhaus listing of 2026-10-27: the entry carried the container name, and Spamhaus names the address pool as the reason for the listing itself. On the removal, 2026-10-30, it answered that the address «is dynamic or CGNAT, and has a extremely poor reputation», blames the provider's open port 25 on that pool and expects the listing to return. A name of your own is one of two conditions for direct delivery and the only one this image can meet; the other is an address whose reputation you own.

- 2026-10-30 **3.5.4**
    - The name postfix announces is configurable and reported. Without `MAILHOST` or a `hostname:` in the compose file, postfix took the container hostname, which docker fills with the first twelve hex digits of the container id: every receiving server was greeted with a name that resolves nowhere. On 2026-10-27 that put a sending address on the Spamhaus lists XBL and CSS, with the entry `212.51.159.193 2026-10-27 15:15:00 d308e74f098d.localdomain`, and one listing hits every service behind that address. `MAILHOST` now writes `myhostname`, a start without any name says in the log what it is about to announce and what it costs, and the README carries the three values that have to agree with the commands to read them.

- 2026-10-23 **3.5.3**
    - The weekly run also rebuilds the version lines 1, 2 and 3, published as `mwaeckerlin/smtp-relay-tls:1`, `:2` and `:3` from the branches `1`, `2` and `3`, so every line gets the security fixes of its base images

- 2026-10-22 **3.5.2**
    - The networks allowed to relay are set with `MYNETWORKS`; unset, the built-in list of loopback and private networks stays
    - `RELAYHOST` sends all outbound mail through one host, written as `host` or `host:port`; unset, the relay delivers directly to the recipient's MX as before
    - A test starts the image and reads the effective postfix configuration for both variables, unset and set

- 2026-09-26 **3.5.1**
    - The image builds on arm64 as well as on amd64 and is published for both under one tag, built and published automatically on every change and every week

- 2026-07-18 **security hardening**
    - Every configuration value from the environment is now validated before use; a malformed value (an embedded newline that could smuggle extra configuration directives, or a path separator in the certificate host name) refuses to start with a clear `invalid <VAR>` error instead of silently producing a broken or unsafe configuration. Covered by the new config-validation test suite (`npm test`).
    - The deprecated `smtpd_use_tls` switch is replaced by its modern equivalent (`smtpd_tls_security_level = may`) — same behaviour, no more deprecation warning on start-up.
    - New standalone compose example (loopback only, with healthcheck and persistent queue volume).

- 2026-07-18 **headless image**
    - The image no longer contains a shell, busybox or a package manager: a compiled `init` binary configures postfix from the environment and starts the postfix master daemon directly. The behaviour (TLS relay with the certificate from `/etc/letsencrypt/live/$MAILHOST/`, optional `OPENDKIM` milter) is unchanged.
    - New `init --healthcheck` probe for Docker healthchecks.
    - Delivery-affecting limits are now configurable with high defaults: `MESSAGE_SIZE_LIMIT` (default 100 GiB, was postfix's 10 MB default) and `SMTP_HARD_ERROR_LIMIT` (default 20) — a legitimate mail is never bounced by an artificial default.
    - The unused `DAYS` environment variable is gone — the image never generated its own certificate; it always expected one in the `letsencrypt` volume.
    - New `DISABLE_DNSBL` switch (default off) strips the DNS-blocklist lookups from the smtpd restrictions — for test/offline stacks whose resolver cannot answer the blocklist zones.
    - The mail queue (`/var/spool/postfix`) is now a declared volume: an accepted mail (`250 Ok`) is the server's responsibility and the sender never retries — a deferred mail must survive container recreates and image updates. Map it to a named volume in production.
