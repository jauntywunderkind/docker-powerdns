FROM alpine:3.12

LABEL \
  MAINTAINER="Christoph Wiechert <wio@psitrax.de>" \
  CONTRIBUTORS="Mathias Kaufmann <me@stei.gr>, Cloudesire <cloduesire-dev@eng.it>"

ENV REFRESHED_AT="2020-06-15" \
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

RUN apk --update --no-cache add pdns pdns-backend-sqlite3 pdns-backend-bind pdns-backend-mysql pdns-backend-pgsql bash \
	mkdir -p /etc/pdns/conf.d

EXPOSE 53/tcp 53/udp

ADD sql/* pdns.conf /etc/pdns/

ADD entrypoint.sh /bin/powerdns

ENTRYPOINT ["powerdns"]
