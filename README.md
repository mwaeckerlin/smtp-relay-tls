# Docker Image for Postfix SMTP Relay with TLS

Configure with mail host name in `MAILHOST` and certificate duration in `DAYS`.

Expects two files in `/etc/letsencrypt/live/${MAILHOST}`:
 - `privkey.pem`: the certificate's private key
 - `fullchain.pem`: the certificate's full chain

This very basic image is intended to be used together with any other docker image that requires a secure SMTP server to send mails. E.g. for [mwaeckerlin/nextcloud](https://hub.docker.com/r/mwaeckerlin/nextcloud), [mwaeckerlin/nodebb](https://hub.docker.com/r/mwaeckerlin/nodebb) or [gitea/gitea](https://hub.docker.com/r/gitea/gitea).

If you don't need TLS, use [mwaeckerlin/smtp-relay](https://hub.docker.com/r/mwaeckerlin/smtp-relay).

See also:
 - [mwaeckerlin/smtp-relay](https://hub.docker.com/r/mwaeckerlin/smtp-relay) for a simple open mail relay
 - [mwaeckerlin/smtp-relay-tls](https://hub.docker.com/r/mwaeckerlin/smtp-relay-tls) for a simple open mail relay with tls
 - [mwaeckerlin/mailforward](https://hub.docker.com/r/mwaeckerlin/mailforward) for a simple mail forwarder without own inbox
 - [mwaeckerlin/postfix](https://hub.docker.com/r/mwaeckerlin/postfix) for a full featured postfix server

## SPF, DKIM and DMARC

### SPF (Sender Policy Framework)

SPF is DNS-only — no server-side configuration required. Add a TXT record to your domain:

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
