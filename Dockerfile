FROM mwaeckerlin/smtp-relay:1 as build
RUN addgroup postfix $SHARED_GROUP_NAME
RUN postconf -e 'smtpd_use_tls = yes'


FROM mwaeckerlin/scratch
ENV CONTAINERNAME "smtp-relay-tls"
ENV DAYS          "36525"
ENV MAILHOST      "localhost"
ENV OPENDKIM      ""

VOLUME /etc/letsencrypt
COPY --from=build / /
ADD start.sh /usr/local/bin/start.sh
USER root
CMD ["/usr/local/bin/start.sh"]