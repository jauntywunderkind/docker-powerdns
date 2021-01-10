#!/bin/sh
set -e

[[ -z "$TRACE" ]] || set -x

# --help, --version
[ "$1" = "--help" ] || [ "$1" = "--version" ] && exec pdns_server $1

# treat everything except -- as exec cmd
[ "${1:0:2}" != "--" ] && exec "$@"

# print a given key-value directory as key=value , typically used for turning /etc/my-service/foo dir into /etc/my-service/conf.d/foo.conf file
printConfd(){
    dir="$1"

	# for each env key
	for key in $dir/*
	do
		# skip directories. TODO: skip directories?
		[ -d $dir/$key ] && continue

		# echo the key=value for pdns etc file, typically /etc/powerdns/conf.d/$1.conf
		val="$(cat $dir/$key)"
		echo "$key=$val"
	done
}

# print a given key-value directory as `export KEY=value`
# TODO: would it be better to parse/filter/transform printConfd
printEnv(){
	dir="$1"

	for key in $dir/*
	do
		# for the init tools, read gsomedb conf elements into this shell's env
		k6="${key:0:6}"
		val="$(cat $dir/$key)"

		# gsqlite is 7 characters, but k6 is only 6, which is what we are checking against
		if [[ $k6 = gmysql ]] || [[ $k6 = gpgsql ]] || [[ $k6 = gsqlit ]]
		then
			# convert to VARIABLE_FORMAT
			keyUp=$(echo $key | tr '[a-z-]' '[A-Z_]')
			# drop leading "g" and export
			echo export ${keyUp:1}=\"${val}\"
		fi
	done
}

# ingest the kubernetes style secret/config directories
doConfigure(){
	local inputDir=$1
	local outputDir=$2
	[ -z "$outputDir" ] && outputDir="$inputDir/conf.d"

	[ -z "$PDNS_CONF_DIRS" ] && PDNS_CONF_DIRS="config,db,secret"
	for subdir in $(echo "$PDNS_CONF_DIRS" | sed "s/,/ /g")
	do
		dir=$inputDir/$subdir

		# write conf files powerdns can read
		local confd=$(printConfd $dir)
		echo $confd > $outputDir/$dir.conf

		# some init scripts require env vars (db related) to run, load that env
		local envs=$(printConfd $dir)
		eval $envs
	done
}
# immediately invoke
doConfigure /etc/powerdns

# Add backward compatibility
[[ "$MYSQL_AUTOCONF" == false ]] && AUTOCONF=false

# Set credentials to be imported into pdns.conf
# TODO: whoa partner, what the heck? why do these have defaults
#  but then we use the undefaulted edition when talking to db's?
#  i feel like the init tools ought have the same chance as the run tools
case "$AUTOCONF" in
  mysql)
    export PDNS_LOAD_MODULES=$PDNS_LOAD_MODULES,libgmysqlbackend.so
    export PDNS_LAUNCH=gmysql
    export PDNS_GMYSQL_HOST=${PDNS_GMYSQL_HOST:-$MYSQL_HOST}
    export PDNS_GMYSQL_PORT=${PDNS_GMYSQL_PORT:-$MYSQL_PORT}
    export PDNS_GMYSQL_USER=${PDNS_GMYSQL_USER:-$MYSQL_USER}
    export PDNS_GMYSQL_PASSWORD=${PDNS_GMYSQL_PASSWORD:-$MYSQL_PASS}
    export PDNS_GMYSQL_DBNAME=${PDNS_GMYSQL_DBNAME:-$MYSQL_DBNAME}
    export PDNS_GMYSQL_DNSSEC=${PDNS_GMYSQL_DNSSEC:-$MYSQL_DNSSEC}
  ;;
  postgres)
    export PDNS_LOAD_MODULES=$PDNS_LOAD_MODULES,libgpgsqlbackend.so
    export PDNS_LAUNCH=${PDNS_LAUNCH:-gpgsql}
    export PDNS_GPGSQL_HOST=${PDNS_GPGSQL_HOST:-$PGSQL_HOST}
    export PDNS_GPGSQL_PORT=${PDNS_GPGSQL_PORT:-$PGSQL_PORT}
    export PDNS_GPGSQL_USER=${PDNS_GPGSQL_USER:-$PGSQL_USER}
    export PDNS_GPGSQL_PASSWORD=${PDNS_GPGSQL_PASSWORD:-$PGSQL_PASS}
    export PDNS_GPGSQL_DBNAME=${PDNS_GPGSQL_DBNAME:-$PGSQL_DBNAME}
    export PDNS_GPGSQL_DNSSEC=${PDNS_GPGSQL_DNSSEC:-$PGSQL_DNSSEC}
    export PGPASSWORD=$PDNS_GPGSQL_PASSWORD
  ;;
  sqlite)
    export PDNS_LOAD_MODULES=$PDNS_LOAD_MODULES,libgsqlite3backend.so
    export PDNS_LAUNCH=gsqlite3
    export PDNS_GSQLITE3_DATABASE=${PDNS_GSQLITE3_DATABASE:-$SQLITE_DBNAME}
    export PDNS_GSQLITE3_PRAGMA_SYNCHRONOUS=${PDNS_GSQLITE3_PRAGMA_SYNCHRONOUS:-$SQLITE_PRAGMA_SYNCHRONOUS}
    export PDNS_GSQLITE3_PRAGMA_FOREIGN_KEYS=${PDNS_GSQLITE3_PRAGMA_FOREIGN_KEYS:-$SQLITE_PRAGMA_FOREIGN_KEYS}
    export PDNS_GSQLITE3_DNSSEC=${PDNS_GSQLITE3_DNSSEC:-$SQLITE_DNSSEC}
  ;;
esac

MYSQLCMD="mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS -r -N"
PGSQLCMD="psql --host=$PGSQL_HOST --username=$PGSQL_USER --port=${PGSQL_PORT:-5432} ${PGSQL_DBNAME}"

# wait for Database come ready
isDBup () {
  case "$PDNS_LAUNCH" in
    gmysql)
      echo "SHOW STATUS" | $MYSQLCMD 1>/dev/null
      echo $?
    ;;
    gpgsql)
      echo "$PGSQL_HOST:$PGSQL_PORT:$PGSQL_DBNAME:$PGSQL_USER:$PGSQL_PASSWORD" > ~/.pgpass
      chmod 0600 ~/.pgpass
      echo "SELECT 1" | $PGSQLCMD 1>/dev/null
      echo $?
    ;;
    *)
      echo 0
    ;;
  esac
}

RETRY=10
until [ `isDBup` -eq 0 ] || [ $RETRY -le 0 ] ; do
  echo "Waiting for database to come up"
  sleep 5
  RETRY=$(expr $RETRY - 1)
done
if [ $RETRY -le 0 ]; then
  if [[ "$MYSQL_HOST" ]]; then
    >&2 echo Error: Could not connect to Database on $MYSQL_HOST:$MYSQL_PORT
    exit 1
  elif [[ "$PGSQL_HOST" ]]; then
    >&2 echo Error: Could not connect to Database on $PGSQL_HOST:$PGSQL_PORT
    exit 1
  fi
fi

# init database and migrate database if necessary
case "$PDNS_LAUNCH" in
  gmysql)
    echo "CREATE DATABASE IF NOT EXISTS $MYSQL_DBNAME;" | $MYSQLCMD
    MYSQLCMD="$MYSQLCMD $MYSQL_DBNAME"
    if [ "$(echo "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = \"$MYSQL_DBNAME\";" | $MYSQLCMD)" -le 1 ]; then
      echo Initializing Database
      cat /etc/powerdns/mysql.schema.sql | $MYSQLCMD
      # Run custom mysql post-init sql scripts
      if [ -d "/etc/powerdns/mysql-postinit" ]; then
        for SQLFILE in $(ls -1 /etc/pdns/mysql-postinit/*.sql | sort) ; do
          echo Source $SQLFILE
          cat $SQLFILE | $MYSQLCMD
        done
      fi
    fi
  ;;
  gpgsql)
    if [[ -z "$(echo "SELECT 1 FROM pg_database WHERE datname = '$PGSQL_DBNAME'" | $PGSQLCMD -t)" ]]; then
      echo "Database did not exist, creating"
      echo "CREATE DATABASE $PGSQL_DBNAME;" | $PGSQLCMD
    fi
    PGSQLCMD="$PGSQLCMD $PGSQL_DBNAME"
    if [[ -z "$(printf '\dt' | $PGSQLCMD -qAt)" ]]; then
      echo Initializing Database
      cat /etc/powerdns/pgsql.schema.sql | $PGSQLCMD
    fi
    rm ~/.pgpass
  ;;
  gsqlite3)
    if [[ ! -f "$PDNS_GSQLITE3_DATABASE" ]]; then
      install -D -d -o pdns -g pdns -m 0755 $(dirname $PDNS_GSQLITE3_DATABASE)
      cat /etc/powerdns/sqlite3.schema.sql | sqlite3 $PDNS_GSQLITE3_DATABASE
      chown pdns:pdns $PDNS_GSQLITE3_DATABASE
    fi
  ;;
esac

# convert all environment variables prefixed with PDNS_ into pdns config directives
PDNS_LOAD_MODULES="$(echo $PDNS_LOAD_MODULES | sed 's/^,//')"
printenv | grep ^PDNS_ | cut -f2- -d_ | while read var; do
  val="${var#*=}"
  var="${var%%=*}"
  var="$(echo $var | sed -e 's/_/-/g' | tr '[:upper:]' '[:lower:]')"
  [[ -z "$TRACE" ]] || echo "$var=$val"
  sed -r -i "s#^[# ]*$var=.*#$var=$val#g" /etc/powerdns/pdns.conf
done

# environment hygiene
for var in $(printenv | cut -f1 -d= | grep -v -e HOME -e USER -e PATH ); do unset $var; done
export TZ=UTC LANG=C LC_ALL=C

# create zones
for zone in $(echo "$PDNS_ZONES" | sed "s/,/ /g")
do
	pdnsutil -v create-zone $zone
done

# prepare graceful shutdown
trap "pdns_control quit" SIGHUP SIGINT SIGTERM

# run the server
pdns_server "$@" &

wait
