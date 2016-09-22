#!/bin/sh
# -*- coding: utf-8; version: 5.4.3 -*-
#
# Copyright 2016 Telefónica I+D
# All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
#

#
# Perform several checks to verify FIWARE Monitoring at Monasca master node
#
# Usage:
#   $0 --help | --version
#   $0 [--verbose] [--monitoring-api=URL] [--mongodb-host=HOST]
#
# Options:
#   -h, --help 			show this help message and exit
#   -V, --version 		show version information and exit
#   -v, --verbose 		enable verbose messages
#   -a, --monitoring-api=URL	perform checks querying Monitoring API
#   -m, --mongodb-host=HOST	perform checks related to remote MongoDB
#

OPTS='h(help)V(version)v(verbose)a(monitoring-api):m(mongodb-host):'
PROG=$(basename $0)
VERSION=$(awk '/-\*-/ {print "v" $(NF-1)}' $0)

# Files
ZOOKEEPER_CONF=/etc/zookeeper/conf/zoo.cfg
MONASCA_API_CONF=/etc/monasca/api-config.yml
PERSISTER_CONF=/etc/monasca/persister-config.yml

# Common definitions
MONASCA_TOPIC=metrics
ZOOKEEPER_PORT=
PERSISTER_MIN_VER=1.0.0
KAFKA_HOME=
KAFKA_MIN_VER=2.11
AUTH_URL=
AUTH_USER=
AUTH_PASS=
AUTH_TOKEN=
BROKER_URL=
BROKER_HOST=
BROKER_PORT=1026
BROKER_MIN_VER=0.27.0
ADAPTER_UDP=
ADAPTER_HOST=
ADAPTER_PORT=
ADAPTER_HOME=
ADAPTER_MIN_VER=1.4.1
METRICS_VALIDITY_HOURS=3

# Command line options defaults
VERBOSE=
MONGODB_HOST=
MONITORING_API=

# Command line processing
OPTERR=
OPTSTR=$(echo :-:$OPTS | sed 's/([-_a-zA-Z0-9]*)//g')
OPTHLP=$(sed -n '21,/^$/ { s/$0/'$PROG'/; s/^#[ ]\?//; p }' $0)
while getopts $OPTSTR OPT; do while [ -z "$OPTERR" ]; do
case $OPT in
'v')	VERBOSE=true;;
'a')	MONITORING_API=$OPTARG;;
'm')	MONGODB_HOST=$OPTARG;
	BROKER_HOST=$MONGODB_HOST;
	BROKER_URL=http://$BROKER_HOST:$BROKER_PORT;;
'h')	OPTERR="$OPTHLP";;
'V')	OPTERR="$VERSION"; printf "$OPTERR\n" 1>&2; exit 1;;
'?')	OPTERR="Unknown option -$OPTARG";;
':')	OPTERR="Missing value for option -$OPTARG";;
'-')	OPTLONG="${OPTARG%=*}";
	OPT=$(expr $OPTS : ".*\(.\)($OPTLONG):.*" '|' '?');
	if [ "$OPT" = '?' ]; then
		OPT=$(expr $OPTS : ".*\(.\)($OPTLONG).*" '|' '?')
		OPTARG=-$OPTLONG
	else
		OPTARG=$(echo =$OPTARG | cut -d= -f3)
		[ -z "$OPTARG" ] && { OPTARG=-$OPTLONG; OPT=':'; }
	fi;
	continue;;
esac; break; done; done
shift $(expr $OPTIND - 1)
[ -z "$OPTERR" -a -n "$*" ] && OPTERR="Too many arguments"

# Show error messages and exit
[ -n "$OPTERR" ] && {
	PREAMBLE=$(echo "$OPTHLP" | sed -n '0,/^Usage:/ p' | head -n -1)
	OPTIONS=$(echo "$OPTHLP" | sed -n "/^Options:/,/^\$/ p")"\n\n"
	EPILOG=$(echo "$OPTHLP" | sed -n "/Environment:/,/^\$/ p")"\n\n"
	USAGE=$(echo "$OPTHLP" | sed -n "/^Usage:/,/^\$/ p")
	TAB=4; LEN=$(echo "$OPTIONS" | awk -F'\t' '/ .+\t/ {print $1}' | wc -L)
	TABSTOPS=$TAB,$(((LEN/TAB+2)*TAB)); WIDTH=${COLUMNS:-$(tput cols)}
	[ "$OPTERR" != "$OPTHLP" ] && PREAMBLE="$OPTERR" && OPTIONS= && EPILOG=
	printf "$PREAMBLE\n\n$USAGE\n\n$OPTIONS" | fmt -$WIDTH -s 1>&2
	printf "$EPILOG" | tr -s '\t' | expand -t$TABSTOPS | fmt -$WIDTH -s 1>&2
	exit 1
}

# Common functions
get_keystone_token() {
	resp_headers=$(curl -s -S -X POST -o /dev/null -D - \
		-H "Content-Type: application/json" \
		-H "Accept: application/json" -d "{
		    \"auth\": {
		        \"identity\": {
		            \"methods\": [
		                \"password\"
		            ],
		            \"password\": {
		                \"user\": {
		                    \"domain\": {
		                        \"id\": \"default\"
		                    },
		                    \"name\": \"$AUTH_USER\",
		                    \"password\": \"$AUTH_PASS\"
		                }
		            }
		        }
		    }
		}" "$AUTH_URL/auth/tokens" | fmt)
	AUTH_TOKEN=$(echo "$resp_headers" | awk '/X-Subject-Token/ {print $NF}')
	test -n "$AUTH_TOKEN"
}

printf_service_url() {
	service_type=$1
	curl='curl -s -S -H "X-Auth-Token: '$AUTH_TOKEN'"'
	service_id=$(eval $curl "$AUTH_URL/services?type=$service_type" \
		| python -mjson.tool | awk -F'"' '/"id"/ {print $4}')
	endpoint_url=$(eval $curl "$AUTH_URL/endpoints?service_id=$service_id" \
		| python -mjson.tool | sed -n '/"interface": "public"/,/}/ p' \
		| awk -F'"' '/"self"/ {print $4}')
	url=$(eval $curl "$endpoint_url" \
		| python -mjson.tool \
		| awk -F'"' '/"url"/ {print $4}')
	printf "$url\n"
}

printf_ok() {
	tput setaf 2; printf "$*\n"; tput sgr0
}

printf_fail() {
	tput setaf 1; printf "$*\n"; tput sgr0
}

printf_warn() {
	tput setaf 3; printf "$*\n"; tput sgr0
}

printf_info() {
	tput setaf 6; printf "$*\n"; tput sgr0
}

printf_skip_no_mongodb() {
	printf "$*"
	if [ -z "$MONGODB_HOST" ]; then
		printf_warn "Skipped (no --mongodb-host provided)"
		return 1
	fi
}

printf_skip_no_adapter() {
	printf "$*"
	if [ -z "$ADAPTER_HOME" ]; then
		printf_warn "Skipped (no local NGSI Adapter found)"
		return 1
	fi
}

printf_kafka_topics() {
	kafka_home=$1
	zookeeper_endpoint=localhost:$2
	$kafka_home/bin/kafka-topics.sh --list --zookeeper $zookeeper_endpoint
}

version_ge() {
	test "$(printf "$1\n$2" | sort -V | head -1)" = "$2"
}

pidof() {
	getpid_cmd="$1"
	output_var=${2:-PID}
	pid=$(eval $getpid_cmd)
	if [ -n "$pid" ]; then
		sleep 3
		pid_again=$(eval $getpid_cmd)
		[ "$pid" != "$pid_again" ] && return 1
	fi
	eval $output_var=$pid
}

# Check Zookeeper configuration
printf "Check Zookeeper configuration... "
if [ ! -r $ZOOKEEPER_CONF ]; then
	printf_fail "Configuration file $ZOOKEEPER_CONF not found"
else
	ZOOKEEPER_PORT=$(awk -F= '/clientPort/ {print $2}' $ZOOKEEPER_CONF)
	printf_ok "$ZOOKEEPER_CONF"
fi

# Check Zookeeper server
printf "Check Zookeeper server... "
NAME=zookeeper
if ! pidof "ps -f -C java | awk '/$NAME/ {print \$2}'" PID; then
	printf_fail "Flapping status: please check logfiles"
elif [ -z "$PID" ]; then
	printf_fail "Not running"
else
	PORTS=$(netstat -lnpt | awk -F: '/'$PID'/ {print $4}' | sort -n | fmt)
	printf_ok "OK: pid=$PID ports=${PORTS:-N/A}"
fi

# Check Kafka installation
printf "Check Kafka installation... "
for DIR in /opt/kafka /opt/kafka_2.*; do
	if [ -d $DIR ]; then
		KAFKA_HOME=$DIR
		LIB=$(find $DIR/libs -name "kafka_*.[0-9].jar" -printf "%f")
		VERSION=$(echo $LIB | awk -F'[-_]' '{print $2}')
		break
	fi
done
if [ -z "$KAFKA_HOME" ]; then
	printf_fail "Not found"
elif ! version_ge $VERSION $KAFKA_MIN_VER; then
	printf_fail "Found version $VERSION, but $KAFKA_MIN_VER is required"
else
	printf_ok "Version $VERSION at $KAFKA_HOME"
fi

# Check Kafka server
printf "Check Kafka server... "
NAME=kafka
if ! pidof "ps -f -C java | awk '/$NAME/ {print \$2}'" PID; then
	printf_fail "Flapping status: please check logfiles"
elif [ -z "$PID" ]; then
	printf_fail "Not running"
else
	PORTS=$(netstat -lnpt | awk -F: '/'$PID'/ {print $4}' | sort -n | fmt)
	printf_ok "OK: pid=$PID ports=${PORTS:-N/A}"
fi

# Check Kafka topics
printf "Check Kafka topics... "
RESULT=$($KAFKA_HOME/bin/kafka-topics.sh \
	--describe \
	--zookeeper localhost:$ZOOKEEPER_PORT \
	--topic $MONASCA_TOPIC | head -1 | expand -t1 | tr ':' '=')
if [ -z "$RESULT" ]; then
	printf_fail "Topic '$MONASCA_TOPIC' not found"
	[ -n "$VERBOSE" ] && printf_kafka_topics "$KAFKA_HOME" "$ZOOKEEPER_PORT"
else
	printf_ok "$RESULT"
fi

# Check MySQL
printf "Check MySQL (Monasca configuration storage)... "
NAME=mysql
PID=$(ps -f -u $NAME | awk -v PID=none '/'$NAME'/ {PID=$2} END {print PID}')
PORTS=$(netstat -lnpt4 | tr : ' ' | awk '/'$PID'/ {print $5}' | sort -n | fmt)
if [ -z "$PID" ]; then
	printf_fail "Not running"
else
	printf_ok "OK: pid=$PID ports=${PORTS:-N/A}"
fi

# Check InfluxDB
printf "Check InfluxDB (Monasca measurements storage)... "
NAME=influxdb
PID=$(ps -f -u $NAME | awk -v PID=none '/'$NAME'/ {PID=$2} END {print PID}')
PORTS=$(netstat -lnpt6 | awk -F: '/'$PID'/ {print $4}' | sort -n | fmt)
if [ -z "$PID" ]; then
	printf_fail "Not running"
else
	printf_ok "OK: pid=$PID ports=${PORTS:-N/A}"
fi

# Check Monasca API server
printf "Check Monasca API server... "
NAME=monasca-api
PID=$(ps -f -C java | awk -v PID=none '/'$NAME'/ {PID=$2} END {print PID}')
PORTS=$(netstat -lnpt6 | awk -F: '/'$PID'/ {print $4}' | sort -n | fmt)
if [ -z "$PID" ]; then
	printf_fail "Not running"
else
	printf_ok "OK: pid=$PID ports=${PORTS:-N/A}"
fi

# Check Monasca API configuration
printf "Check Monasca API configuration... "
AUTH_USER=$(awk '
	/adminUser/	{ print $2 }
	' $MONASCA_API_CONF 2>/dev/null | tr -d \")
AUTH_PASS=$(awk '
	/adminPassword/	{ print $2 }
	' $MONASCA_API_CONF 2>/dev/null | tr -d \")
AUTH_URL=$(awk '
	BEGIN		{ PROTOCOL="http" }
	/Https: *True/	{ PROTOCOL="https" }
	/serverVIP/	{ HOST=$2 }
	/serverPort/	{ PORT=$2 }
	END		{ if (HOST!="" && PORT!="")
				printf "%s://%s:%d/v3", PROTOCOL, HOST, PORT;
			}
	' $MONASCA_API_CONF 2>/dev/null)
if [ ! -r $MONASCA_API_CONF ]; then
	printf_fail "Configuration file $MONASCA_API_CONF not found"
elif [ -z "$AUTH_USER" ]; then
	printf_fail "No 'adminUser' value found at $MONASCA_API_CONF"
elif [ -z "$AUTH_PASS" ]; then
	printf_fail "No 'adminPassword' value found at $MONASCA_API_CONF"
elif [ -z "$AUTH_URL" ]; then
	printf_fail "No 'serverVIP' or 'serverPort' found at $MONASCA_API_CONF"
else
	printf_ok "$MONASCA_API_CONF"
fi

# Check Monasca Notification server
printf "Check Monasca Notification server... "
NAME=monasca-notification
PID=$(ps -ef | fgrep python | awk '/'$NAME'/ {print $2}' | fmt)
if [ -z "$PID" ]; then
	printf_fail "Not running"
else
	printf_ok "OK: pid=$PID"
fi

# Check Monasca Persister server
printf "Check Monasca Persister server... "
NAME=monasca-persister
PID=$(ps -f -C java | awk '/'$NAME'/ {print $2}')
LIB_VER=$(ps -f -C java \
	| sed -n '/'$NAME'/ { s/.*'$NAME'-\?\([^:]*\).*/\1/; s/\.jar//; p }')
VERSION="${PID:+${LIB_VER:-N/A}}"
if [ -z "$PID" ]; then
	printf_fail "Not running"
elif ! version_ge $VERSION $PERSISTER_MIN_VER; then
	printf_fail "Found version $VERSION, but $PERSISTER_MIN_VER is required"
elif [ -n "$MONGODB_HOST" -a "$VERSION" = "${VERSION%-FIWARE}" ]; then
	printf_fail "Not found required FIWARE-specific version"
else
	printf_ok "OK: pid=$PID version=$VERSION"
fi

# Check Monasca Persister configuration
printf "Check Monasca Persister configuration... "
if [ ! -r $PERSISTER_CONF ]; then
	printf_fail "Configuration file $PERSISTER_CONF not found"
else
	printf_ok "$PERSISTER_CONF"
fi

# Check Keystone credentials
printf "Check Keystone credentials... "
if get_keystone_token; then
	printf_ok "OK"
else
	printf_fail "ERROR"
fi

# Check Monitoring API
printf "Check Monitoring API... "
SERVICE_CATALOG_MONITORING_URL=$(printf_service_url "monitoring")
URL=${MONITORING_API:=$SERVICE_CATALOG_MONITORING_URL}
if ! curl -s -S "$URL/monitoring/" 2>/dev/null | fgrep -q NOT_FOUND; then
	printf_fail "Could not connect to Monitoring API at $URL"
elif [ "$URL" != "$SERVICE_CATALOG_MONITORING_URL" ]; then
	printf_ok "$URL"
	printf_warn "* Catalog URL '$SERVICE_CATALOG_MONITORING_URL' differs"
else
	printf_ok "$URL"
fi

# Check Monitoring API region entities
printf "Check Monitoring API region entities... "
CURRENT_TIMESTAMP=$(date -u +%s)
THRESHOLD_TIMESTAMP=$((CURRENT_TIMESTAMP - METRICS_VALIDITY_HOURS * 3600))
UPGRADE_WARN=$(printf_warn " not upgraded to new monitoring" | tr -d '\n')
QUERY=monitoring/regions
REGIONS=$(curl -s -S $MONITORING_API/$QUERY 2>/dev/null \
	| python -mjson.tool \
	| awk -F'"' '/"id"/ {print $4}' | sort)
if [ -z "$REGIONS" ]; then
	printf_fail "Could not connect to Monitoring API at $MONITORING_API"
else
	printf_info "count=$(echo $REGIONS | wc -w)"
	for REGION in $REGIONS; do
		QUERY=monitoring/regions/$REGION
		RESULT=$(curl -s -S $MONITORING_API/$QUERY)
		IS_NEW_MONITORING=$(expr "$RESULT" : ".*\(components\).*")
		MONITORING_API_DATE=$(echo "$RESULT" \
			| sed 's/.*"timestamp":\( \)\?"\([^"]*\)".*/\2/g')

		MONITORING_TIMESTAMP=$(date -u -d "$MONITORING_API_DATE" +%s)
		DIFF_SECS=$((CURRENT_TIMESTAMP - MONITORING_TIMESTAMP))
		DIFF_STR=$(date -d @$DIFF_SECS +'%j %H %M %S' | awk '
			{ printf "%d days %dh %dm %ds\n", $1-1, $2, $3, $4 }')

		if [ -n "$IS_NEW_MONITORING" ]; then
			eval MONITORING_TIMESTAMP_$REGION=$MONITORING_TIMESTAMP
			WARN=""
		else
			WARN="$UPGRADE_WARN"
		fi

		LINE="$REGION: timestamp=\"$MONITORING_API_DATE\""
		if [ $MONITORING_TIMESTAMP -lt $THRESHOLD_TIMESTAMP ]; then
			printf_fail "* ${LINE} (${DIFF_STR} outdated)${WARN}"
		else
			printf_ok "* ${LINE}${WARN}"
		fi
	done
	MONITORING_REGIONS_REGEX=$(echo $REGIONS | sed 's/ /\\|/g')
fi

# Check ContextBroker region entities at MongoDB
printf_skip_no_mongodb "Check ContextBroker regions... " && {
MONGO_QUERY='{"_id.type": "region"}, {"attrs._timestamp.value":1, "modDate":1}'
MONGO_RESULTS=$(mongo --quiet --eval "DBQuery.shellBatchSize=100; \
	db.entities.find($MONGO_QUERY).shellPrint()" \
	$MONGODB_HOST/orion 2>/dev/null)
if [ -z "$(which mongo)" ]; then
	printf_warn "Skipped: no 'mongo' client available"
elif expr "$MONGO_RESULTS" : ".*Error.*" >/dev/null; then
	printf_fail "Could not connect to Mongo database at $MONGODB_HOST"
else
	printf_info "count=$(echo "$MONGO_RESULTS" | wc -l)"
	MONGO_TIMESTAMPS=$(echo "$MONGO_RESULTS" | awk -F'[ "]' '
		{ print $12 ":" substr($44, 1, 10) ":" $(NF-1) }' | sort)
	DATE_FMT="%d/%m/%Y %T %Z"
	for ITEM in $MONGO_TIMESTAMPS; do
		REGION=${ITEM%%:*}
		REGION_ATTR_TIMESTAMP=$(echo $ITEM | cut -d: -f2)
		LAST_UPDATE_TIMESTAMP=$(echo $ITEM | cut -d: -f3)
		eval MONITORING_TIMESTAMP=\${MONITORING_TIMESTAMP_$REGION:-0}

		DATE=$(date -d @$MONITORING_TIMESTAMP +"$DATE_FMT")
		INFO="monitoring=$DATE"

		DATE=$(date -d @$LAST_UPDATE_TIMESTAMP +"$DATE_FMT")
		if [ $LAST_UPDATE_TIMESTAMP -eq $MONITORING_TIMESTAMP ]; then
			INFO="$INFO modDate=$DATE"
		else
			WARN=$(printf_warn "modDate=$DATE" | tr -d '\n')
			INFO="$INFO $WARN"
		fi

		DATE=$(date -d @$REGION_ATTR_TIMESTAMP +"$DATE_FMT")
		if [ $REGION_ATTR_TIMESTAMP -eq $MONITORING_TIMESTAMP ]; then
			INFO="$INFO _timestamp=$DATE"
		else
			WARN=$(printf_warn "_timestamp=$DATE" | tr -d '\n')
			INFO="$INFO $WARN"
		fi

		if [ $(expr $REGION : "$MONITORING_REGIONS_REGEX") -eq 0 ]; then
			printf_fail "* $REGION: not configured for monitoring"
		elif [ $MONITORING_TIMESTAMP -eq 0 ]; then
			printf_info "* $REGION: not upgraded to new monitoring"
		else
			printf_ok "* $REGION: $INFO"
		fi
	done
fi
}

# Check ContextBroker version
printf_skip_no_mongodb "Check ContextBroker version... " && {
VERSION=$(curl -s -S -H "Accept: application/json" $BROKER_URL/version \
	| awk -F'"' '/version/ {print $4}')
if ! version_ge $VERSION $BROKER_MIN_VER; then
	printf_fail "Found version $VERSION, but $BROKER_MIN_VER is required"
else
	printf_ok "Version $VERSION at $BROKER_HOST"
fi
}

# Check NGSI Adapter endpoint
printf_skip_no_mongodb "Check NGSI Adapter endpoint... " && {
ADAPTER_UDP=$(awk -F'"' '/^ *remoteEndpoint/ {print $2}' $PERSISTER_CONF)
if [ -z "$ADAPTER_UDP" ]; then
	printf_fail "Could not find value at configuration file $PERSISTER_CONF"
else
	ADAPTER_HOST=${ADAPTER_UDP%:*}
	ADAPTER_PORT=${ADAPTER_UDP#*:}
	printf_ok "$ADAPTER_UDP"
fi
}

# Check NGSI Adapter location
printf_skip_no_mongodb "Check NGSI Adapter location... " && {
for DIR in  /opt/fiware/ngsi_adapter; do
	if [ -d $DIR ]; then
		ADAPTER_HOME=$DIR
		VERSION=$(awk -F'"' '/"version"/ {print $4}' $DIR/package.json)
		break
	fi
done
if [ "$ADAPTER_HOST" != "127.0.0.1" -a "$ADAPTER_HOST" != "localhost" ]; then
	ADAPTER_HOME=
	printf_ok "Installed at remote host $ADAPTER_HOST"
elif [ -z "$ADAPTER_HOME" ]; then
	printf_fail "Not found"
elif ! version_ge $VERSION $ADAPTER_MIN_VER; then
	printf_fail "Found version $VERSION, but $ADAPTER_MIN_VER is required"
else
	printf_ok "Version $VERSION at $ADAPTER_HOME"
fi
}

# Check NGSI Adapter server
printf_skip_no_mongodb "Check NGSI Adapter server... " && {
RESULT=$(nc -vz -u $ADAPTER_HOST $ADAPTER_PORT 2>&1 | fgrep "succeeded")
if [ -z "$RESULT" ]; then
	printf_fail "Endpoint $ADAPTER_UDP unreachable"
else
	printf_ok "Successfully connected to $ADAPTER_UDP"
fi
}

# Check NGSI Adapter process
printf_skip_no_adapter "Check NGSI Adapter process... " && {
NAME=ngsi_adapter
PID=$(ps -f -C nodejs | awk '/'$NAME'\/adapter/ {print $2}')
ENV=$(xargs --null --max-args=1 < /proc/$PID/environ)
PORTS=$(netstat -anp \
	| egrep 'udp|LISTEN' \
	| awk '/'${PID:-none}'/ { sub(/0.0.0.0:/,"/"); print toupper($1) $4 }' \
	| sort  | fmt)
if [ -z "$PID" ]; then
	printf_fail "Not running"
else
	printf_ok "OK: pid=$PID ports=${PORTS:-N/A}"
fi
}

# Check NGSI Adapter configuration
printf_skip_no_adapter "Check NGSI Adapter configuration... " && {
PARSERS_PATH=$(echo "$ENV" | awk -F= '/ADAPTER_PARSERS_PATH/ {print $2}')
BROKER_URL=$(echo "$ENV" | awk -F= '/ADAPTER_BROKER_URL/ {print $2}')
if [ -z "$PARSERS_PATH" ]; then
	printf_fail "Could not find NGSI Adapter parsers path"
elif [ -z "$BROKER_URL" ]; then
	printf_fail "Could not find NGSI Adapter ContextBroker URL"
else
	printf_ok "parsersPath=$PARSERS_PATH brokerUrl=$BROKER_URL"
fi
}

# Check NGSI Adapter parser for Monasca
printf_skip_no_adapter "Check NGSI Adapter parser for Monasca... " && {
PARSER_FILE=
PARSER_DIRS=$(echo $PARSERS_PATH | cut -d: -f2- | tr ':' ' ')
for DIR in $PARSER_DIRS; do
	PARSER_FILE=$(ls -1 $DIR/monasca_*.js)
done
if [ -z "$PARSER_FILE" ]; then
	printf_fail "Could not find parser at $PARSERS_PATH"
else
	PACKAGE=$(dirname $PARSER_FILE)/../package.json
	VERSION=$(awk -F'"' '/version/ {print $4}' $PACKAGE 2>/dev/null)
	printf_ok "Version ${VERSION:-N/A} at $PARSER_FILE"
fi
}
