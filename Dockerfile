FROM alpine:3.12

LABEL \
	MAINTAINERS="jauntywunderkind <jaunty+wunder+kind+dev@voodoowarez.com>" \
	CONTRIBUTORS="Christoph Wiechert <wio@psitrax.de>, Mathias Kaufmann <me@stei.gr>, Cloudesire <cloduesire-dev@eng.it>"
VOLUME ["/etc/powerdns/kube/config", "/etc/powerdns/kube/db", "/etc/powerdns/kube/secret"]
ENV REFRESHED_AT="2020-1-9" \
	PDNS_VERSION=4.4.0 \
	PDNS_ETC_FILE=/etc/powerdns/pdns.conf \
	PDNS_KUBE_ETC_DIRS=/etc/powerdns/kube \
	PDNS_CONFD_DIR=/etc/powerdns/conf.d \
	PDNS_SEED_FILE=/opt/docker-powerdns/pgsql.schema.sql
EXPOSE 53/tcp 53/udp 53000/tcp 80/tcp
ENTRYPOINT ["pdns-entrypoint"]


# via https://github.com/psi-4ward/docker-powerdns/blob/9660fe5c361d90e853705626657006b3755ade72/Dockerfile
RUN apk --update add bash curl libpq sqlite-libs libstdc++ libgcc mariadb-client mariadb-connector-c lua-dev curl-dev postgresql-client sqlite && \
	apk add --virtual build-deps \
	g++ make mariadb-dev postgresql-dev sqlite-dev curl boost-dev mariadb-connector-c-dev && \
	curl -sSL https://downloads.powerdns.com/releases/pdns-$PDNS_VERSION.tar.bz2 | tar xj -C /tmp && \
	cd /tmp/pdns-$PDNS_VERSION && \
	./configure --prefix="" --exec-prefix=/usr \
	  --with-modules="bind gmysql gpgsql gsqlite3 lua2" && \
	make && make install-strip && cd / && \
	cp /usr/lib/libboost_program_options.so* /tmp && \
	apk del --purge build-deps && \
	mv /tmp/lib* /usr/lib/ && \
	rm -rf /tmp/pdns-$PDNS_VERSION /var/cache/apk/*

RUN mkdir -p $PDNS_CONFD_DIR $PDNS_KUBE_ETC_DIRS /var/run/pdns && \
	addgroup -S pdns 2>/dev/null && \
	adduser -S -D -h /opt/docker-powerdns -s /bin/sh -G pdns -g pdns pdns 2>/dev/null && \
	touch $PDNS_CONFD_DIR/_empty.conf /var/run/pdns/.gitkeep && \
	chown pdns:pdns $PDNS_CONFD_DIR $PDNS_CONFD_DIR/_empty.conf $PDNS_KUBE_ETC_DIRS /var/run/pdns && \
	ln -sf /opt/docker-powerdns/pdns.conf /etc/powerdns/pdns.conf && \
	ln -sf /etc/powerdns/pdns.conf /etc/pdns.conf && \
	ln -sf \
		/opt/docker-powerdns/pdns-curl \
		/opt/docker-powerdns/pdns-entrypoint \
		/opt/docker-powerdns/pdns-healthcheck \
		/opt/docker-powerdns/pdns-healthcheck-api \
		/opt/docker-powerdns/pdns-healthcheck-domain \
		/opt/docker-powerdns/pdns-healthcheck-pg \
		/opt/docker-powerdns/pdns-kube-etc \
		/opt/docker-powerdns/pdns-preseed-etc \
		/opt/docker-powerdns/pdns-preseed-pg \
		/opt/docker-powerdns/pdns-psql \
		/opt/docker-powerdns/pdns-script-helpers \
		/bin/

ADD sql pdns.conf pdns-entrypoint pdns-healthcheck pdns-healthcheck-api pdns-healthcheck-domain pdns-healthcheck-pg pdns-kube-etc pdns-psql pdns-curl pdns-preseed-etc pdns-preseed-pg pdns-script-helpers /opt/docker-powerdns/
USER pdns:pdns
