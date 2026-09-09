# Inherits the accumulated postfix configuration (main.cf) from the
# published mwaeckerlin/smtp-relay image — a locally built image takes
# precedence, otherwise Docker pulls it from the hub. The build stage
# installs postfix fresh (very-base has the package manager the
# headless parent no longer ships) and layers this image's deltas on
# the parent's main.cf.
FROM mwaeckerlin/smtp-relay:3 AS parent

FROM mwaeckerlin/very-base AS init
RUN $PKG_INSTALL g++
COPY init.cpp .
RUN g++ -static -Os -flto=auto -fno-rtti -ffunction-sections -fdata-sections \
        -Wl,--gc-sections -Wl,-s -std=c++20 -o init init.cpp
RUN strip -s -R .comment -R .gnu.version --strip-unneeded init

FROM mwaeckerlin/very-base AS build
RUN $PKG_INSTALL postfix ca-certificates
RUN mkdir /mail
RUN $ALLOW_USER /mail
RUN mkdir -p /tmp
RUN chmod 1777 /tmp
COPY --from=parent /etc/postfix/main.cf /etc/postfix/main.cf
RUN addgroup postfix $SHARED_GROUP_NAME
# modern replacement for the deprecated `smtpd_use_tls = yes`:
# opportunistic STARTTLS with the mounted certificate
RUN postconf -e 'smtpd_tls_security_level = may'
# master execs every service directly — no chroot jail exists in the
# headless image, so normalize all master.cf entries to chroot=n.
RUN postconf -F '*/*/chroot=n'
RUN newaliases
COPY --from=init init /usr/bin/init
# These are shell scripts driven by the postfix(1) wrapper — the
# headless image boots master directly via init, so they must not ship.
RUN rm -f /usr/libexec/postfix/postfix-script \
          /usr/libexec/postfix/post-install \
          /usr/libexec/postfix/postfix-wrapper \
          /usr/libexec/postfix/postfix-tls-script \
          /usr/libexec/postfix/postmulti-script

# Collect only the binaries, shared libraries and configs the runtime
# actually needs into /root/ — no shell, no package manager, no
# busybox. musl's `ldd` accepts exactly ONE file per invocation, so
# deps are gathered in a per-file loop; /lib/ld-musl-x86_64.so.1 is
# the ELF interpreter and listed explicitly.
RUN tar cph \
        /etc/postfix /var/spool/postfix /var/lib/postfix /mail \
        /etc/passwd /etc/group /etc/services /etc/nsswitch.conf \
        /etc/ssl/certs /etc/ssl/cert.pem /usr/share/ca-certificates \
        /usr/sbin/postconf /usr/sbin/postmap /usr/sbin/postalias \
        /usr/sbin/postsuper /usr/sbin/postlog /usr/sbin/postqueue \
        /usr/sbin/postdrop /usr/sbin/postcat /usr/sbin/sendmail \
        /usr/libexec/postfix /usr/lib/postfix \
        /usr/share/icu \
        /usr/bin/init /lib/ld-musl-x86_64.so.1 /tmp \
        $(for f in /usr/sbin/post* /usr/sbin/sendmail \
                   /usr/libexec/postfix/* /usr/lib/postfix/*.so*; do \
              ldd "$f" 2>/dev/null | sed -n 's,.* => \([^ ]*\) .*,\1,p'; \
          done | sort -u) \
    | tar xpC /root/

FROM mwaeckerlin/scratch
ENV CONTAINERNAME="smtp-relay-tls" \
    MAILHOST="localhost" \
    OPENDKIM="" \
    DISABLE_DNSBL="" \
    MESSAGE_SIZE_LIMIT="107374182400" \
    SMTP_HARD_ERROR_LIMIT="20"
EXPOSE 25
VOLUME /mail
VOLUME /etc/letsencrypt
# The mail queue MUST be persistent: postfix answers 250 as soon as a
# mail is fsync'ed into the queue — from then on the server owns
# delivery and the sender never retries. A deferred mail sitting here
# through a container recreate would otherwise vanish silently. Map
# this to a NAMED volume in production (an anonymous one does not
# survive `down`).
VOLUME /var/spool/postfix
# Trade-off: the postfix master process must start as root to bind
# port 25 and manage the queue; every service then drops privileges to
# the postfix user per master.cf. See README.
USER root
ENTRYPOINT ["/usr/bin/init"]
COPY --from=build /root/ /
