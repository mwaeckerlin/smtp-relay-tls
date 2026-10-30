# Docker Image for Postfix SMTP Relay with TLS

Configure with mail host name in `MAILHOST`.

Expects two files in `/etc/letsencrypt/live/${MAILHOST}`:
 - `privkey.pem`: the certificate's private key
 - `fullchain.pem`: the certificate's full chain

This very basic image is intended to be used together with any other docker image that requires a secure SMTP server to send mails. E.g. for [mwaeckerlin/nextcloud](https://hub.docker.com/r/mwaeckerlin/nextcloud), [mwaeckerlin/nodebb](https://hub.docker.com/r/mwaeckerlin/nodebb) or [gitea/gitea](https://hub.docker.com/r/gitea/gitea).

If you don't need TLS, use [mwaeckerlin/smtp-relay](https://hub.docker.com/r/mwaeckerlin/smtp-relay).

## Headless image

The image is headless: a small compiled `init` binary configures postfix from the environment and execs the postfix `master` daemon in container mode — no shell, no busybox, no package manager in the shipped image. `init --healthcheck` TCP-probes the SMTP listener on 127.0.0.1:25 and can be wired as a Docker healthcheck:

```yaml
healthcheck:
  test: ["CMD", "/usr/bin/init", "--healthcheck"]
```

Trade-off: the container starts as root — the postfix master needs it to bind port 25 and manage the mail queue — and every postfix service then drops privileges to the unprivileged `postfix` user per master.cf.

## Mail queue persistence

Postfix answers `250 Ok` as soon as a mail is safely written (fsync) into its queue — from that moment the server owns delivery and the sender never retries. A deferred mail (target greylisting, target briefly down) can sit in the queue for hours or days. **Map `/var/spool/postfix` to a named volume**, otherwise every container recreate or image update silently destroys accepted-but-undelivered mail.

## The name this relay announces — set it, or the address gets blocklisted

**Postfix greets every receiving server with `myhostname`, and without a name of your own that is the id of the container.** Docker fills the container hostname with the first twelve hex digits of the container id, postfix takes `myhostname` from it, and `smtp_helo_name = $myhostname` sends it out on every connection. A name like `d308e74f098d.localdomain` resolves nowhere.

What that costs, measured on 2026-10-27 on a cluster running the sibling image `mwaeckerlin/smtp-relay`: Spamhaus listed the sending address on XBL and CSS, with the entry

```
212.51.159.193  2026-10-27 15:15:00  d308e74f098d.localdomain
```

The mail behind it was a calendar invitation from Nextcloud. One listing hits every service behind that address, because the address is what gets listed, not the container.

**The entry carries that name; the reason Spamhaus gives for the listing is the address pool.** On the removal, 2026-10-30, it answered: the address «is dynamic or CGNAT, and has a extremely poor reputation due to the amount of spam, malware, and other internet abuse associated with it», and it names the provider's open port 25 on that pool as the cause, with the listing likely to return. So a name of your own is one of two conditions for direct delivery, and the only one this image can meet. The other is an address whose reputation you own: a static one from the provider, or `RELAYHOST` towards a server that has one.

**`MAILHOST` names the host, and this image already uses it for the certificate path.** Set it to a real name and postfix announces it:

```yaml
smtp:
  image: mwaeckerlin/smtp-relay-tls
  hostname: mail.example.com
  environment:
    MAILHOST: mail.example.com
```

The default `localhost` is no such name: it resolves to the loopback address everywhere. Left at the default and without `hostname:`, the start writes a warning naming the container id it is about to announce.

**Which name belongs there: the one the PTR record of the outgoing address carries.** Three values have to agree, and all three are readable:

```
hostname: mail.example.com         in the compose file
dig +short mail.example.com        the address the mail leaves from
dig +short -x <that address>       mail.example.com
```

The certificate under `/etc/letsencrypt/live/$MAILHOST/` carries the same name, so one name serves both.

Google, Microsoft and Yahoo require that record in their published sender rules: «Ensure that sending domains or IPs have valid forward and reverse DNS records» (Google, [Email sender guidelines](https://support.google.com/mail/answer/81126)), «Have a valid forward and reverse DNS record for your sending IPs» (Yahoo, [Sender Best Practices](https://senders.yahooinc.com/best-practices/)), «Email servers must have valid reverse DNS records» (Microsoft, Outlook.com postmaster policies).

**A correct name alone does not get the mail through.** A relay that delivers directly sends on behalf of your domains, and a receiver asks whether your domain authorises this address. Without SPF, Google answers `5.7.26 unauthenticated mail` and the message bounces. Publish for every sending domain:

```
example.com.  IN TXT  "v=spf1 mx ip4:<the outgoing address> -all"
```

and sign with DKIM through `OPENDKIM` below. The full records are in «SPF, DKIM and DMARC» at the end of this file.

A complete stack with Nextcloud and WordPress sending through a relay is in [`docker-compose.example.yml`](../smtp-relay/docker-compose.example.yml) of the sibling image; it differs only in the image name and the certificate volume.

## Relay networks and upstream relay

- **`MYNETWORKS`** (default `127.0.0.1/32 192.168.0.0/16 172.16.0.0/12 10.0.0.0/8`): the client networks allowed to relay through this server, in postfix `mynetworks` syntax. Narrow it to the networks of the services that really send mail.
- **`RELAYHOST`** (default empty: deliver directly to the recipient's MX): `host` or `host:port` of an upstream SMTP server that takes all outbound mail, written to postfix as `relayhost = [host]:port` (no MX lookup).

Pinned by `tests/env-config.sh` (`npm test`), which reads the effective `postconf` value with and without each variable.

## DNS blocklists

The smtpd restrictions include DNSBL/RHSBL lookups (manitu, spamhaus). Set **`DISABLE_DNSBL`** to any non-empty value to strip them — for test or offline stacks whose resolver cannot answer the blocklist zones (each lookup would stall the SMTP dialogue until the resolver timeout). Trade-off: without the blocklists, known-bad senders are no longer rejected at connect time; leave it unset in production.

## Delivery-affecting limits

Both limits are deliberately high by default and configurable — a legitimate mail must never bounce because of an artificial default:

- **`MESSAGE_SIZE_LIMIT`** (bytes, default `107374182400` = 100 GiB, `0` = unlimited): maximum accepted message size; `mailbox_size_limit` is pinned to the same value.
- **`SMTP_HARD_ERROR_LIMIT`** (default `20`, the postfix standard): hard SMTP protocol errors per session before the connection is dropped.

## Input validation

Every environment value is whitelist-validated at start-up before it is fed to `postconf` or used as the certificate path segment — a malformed value (embedded newline, a `/` in `MAILHOST`, out-of-range number) aborts the start with a clear `invalid <VAR>` error instead of rendering a broken or unsafe configuration. Pinned by `tests/config-validation.sh` (`npm test`).

See also:
 - [mwaeckerlin/smtp-relay](https://hub.docker.com/r/mwaeckerlin/smtp-relay) for a simple open mail relay
 - [mwaeckerlin/smtp-relay-tls](https://hub.docker.com/r/mwaeckerlin/smtp-relay-tls) for a simple open mail relay with tls
 - [mwaeckerlin/mailforward](https://hub.docker.com/r/mwaeckerlin/mailforward) for a simple mail forwarder without own inbox
 - [mwaeckerlin/postfix](https://hub.docker.com/r/mwaeckerlin/postfix) for a full featured postfix server

## SPF, DKIM and DMARC

### SPF (Sender Policy Framework)

SPF is DNS-only — no server-side configuration required. Add a TXT record to your domain:

```
Name:  example.com
Type:  TXT
Value: v=spf1 mx ~all
```

Replace `~all` (softfail) with `-all` (hardfail) once all legitimate senders are listed.

---

### DKIM (DomainKeys Identified Mail)

DKIM signing is optional. Connect this relay to an external OpenDKIM milter via the `OPENDKIM` environment variable:

```yaml
smtp-relay-tls:
  image: mwaeckerlin/smtp-relay-tls
  environment:
    MAILHOST: mail.example.com
    OPENDKIM: opendkim        # host[:port], default port 10026
  volumes:
    - /etc/letsencrypt:/etc/letsencrypt:ro

opendkim:
  image: mwaeckerlin/opendkim
  environment:
    DOMAIN:   example.com    # required
    SELECTOR: mail            # optional, default: mail
  volumes:
    - dkim-keys:/etc/opendkim/keys
```

On first start, OpenDKIM prints the DNS record to publish:

```
Name:  mail._domainkey.example.com
Type:  TXT
Value: v=DKIM1; h=sha256; k=rsa; p=<public-key>
```

To disable DKIM, leave `OPENDKIM` empty or unset.

---

### DMARC (Domain-based Message Authentication, Reporting and Conformance)

DMARC is DNS-only. Add a TXT record:

```
Name:  _dmarc.example.com
Type:  TXT
Value: v=DMARC1; p=none; rua=mailto:dmarc-reports@example.com
```

Start with `p=none` to monitor, then move to `p=quarantine` or `p=reject`.
