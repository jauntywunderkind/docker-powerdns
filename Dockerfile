FROM alpine:3.12

LABEL \
  MAINTAINERS="jauntywunderkind <jaunty+wunder+kind+dev@voodoowarez.com>" \
  CONTRIBUTORS="Christoph Wiechert <wio@psitrax.de>, Mathias Kaufmann <me@stei.gr>, Cloudesire <cloduesire-dev@eng.it>"

VOLUME ["/etc/powerdns/config", "/etc/powerdns/conf.d", "/etc/powerdns/db", "/etc/powerdns/secret"]

ENV REFRESHED_AT="2020-07-4" \
    POWERDNS_VERSION=4.3.0 \
    AUTOCONF=pgsql \
    MYSQL_HOST="mysql" \
    MYSQL_PORT="3306" \
    MYSQL_USER="root" \
    MYSQL_PASS="root" \
    MYSQL_DB="pdns" \
    MYSQL_DNSSEC="no" \
    PGSQL_HOST="postgres" \
    PGSQL_PORT="5432" \
    PGSQL_USER="postgres" \
    PGSQL_PASS="postgres" \
    PGSQL_DB="pdns" \
    SQLITE_DB="pdns.sqlite3"

# via https://github.com/psi-4ward/docker-powerdns/blob/9660fe5c361d90e853705626657006b3755ade72/Dockerfile
RUN apk --update add bash libpq sqlite-libs libstdc++ libgcc mariadb-client mariadb-connector-c lua-dev curl-dev && \
    apk add --virtual build-deps \
      g++ make mariadb-dev postgresql-dev sqlite-dev curl boost-dev mariadb-connector-c-dev && \
    curl -sSL https://downloads.powerdns.com/releases/pdns-$POWERDNS_VERSION.tar.bz2 | tar xj -C /tmp && \
    cd /tmp/pdns-$POWERDNS_VERSION && \
    ./configure --prefix="" --exec-prefix=/usr \
      --with-modules="bind gmysql gpgsql gsqlite3 lua2" && \
    make && make install-strip && cd / && \
    mkdir -p /etc/powerdns/config /etc/powerdns/conf.d /etc/powerdns/db /etc/powerdns/secret && \
    addgroup -S pdns 2>/dev/null && \
    adduser -S -D -H -h /var/empty -s /bin/false -G pdns -g pdns pdns 2>/dev/null && \
    cp /usr/lib/libboost_program_options.so* /tmp && \
    apk del --purge build-deps && \
    mv /tmp/lib* /usr/lib/ && \
    rm -rf /tmp/pdns-$POWERDNS_VERSION /var/cache/apk/*

ADD sql/ pdns.conf /etc/powerdns/
ADD entrypoint.sh /bin/

EXPOSE 53/tcp 53/udp 53000/tcp 80/tcp

ENTRYPOINT ["entrypoint.sh"]
