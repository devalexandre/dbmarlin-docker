#!/bin/bash

Cyan='\033[0;36m'
Red='\033[0;31m'
Reset='\033[0m'

if (( $EUID == 0 )); then
    echo "Please don't run as root. We recommend you create a dbmarlin user."
fi

DIR="$(cd "$(dirname "$0")" && pwd)"

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$DIR/lib:$DIR/postgresql/lib
#echo "Using LD_LIBRARY_PATH" $LD_LIBRARY_PATH

usage () {
  echo "./start.sh -t [tomcat] -p [postgres] -n [nginx] -h [help]"
  exit
}

while getopts tpnh option
do
case "${option}"
in
t) TOMCAT=1;;
p) POSTGRES=1;;
n) NGINX=1;;
h) HELP=1;;
esac
done

if [[ ! -z "$HELP" ]]; then
    usage
fi

if [[ -z "$POSTGRES" && -z "$TOMCAT" && -z "$NGINX" ]]; then
    echo "Starting all processes"
    TOMCAT=1
    POSTGRES=1
    NGINX=1
fi

if [[ ! -z $POSTGRES ]]; then
    echo "Starting postgresql"
    cd "$DIR/postgresql"
    PGDATA=$DIR/postgresql/data
    $DIR/postgresql/bin/pg_ctl -D $PGDATA -l $DIR/postgresql/logfile start
    while [ ! -f "$DIR/postgresql/data/postmaster.pid" ]; do cat $DIR/postgresql/logfile; sleep 1; done; 
    printf "${Cyan}postgresql started.${Reset}\n"
    cat $DIR/postgresql/data/postmaster.pid
fi

if [[ ! -z $TOMCAT ]]; then
    echo "Starting tomcat"
    cd "$DIR/tomcat/bin/"
    ./startup.sh
    while [ ! -f "$DIR/tomcat/bin/catalina.pid" ]; do echo "waiting for tomcat become ready..."; sleep 1; done; 
    printf "${Cyan}tomcat started.${Reset}\n"
    cat catalina.pid
fi

if [[ ! -z $NGINX ]]; then
    echo "Starting nginx"
    cd "$DIR/nginx"
    ./nginx -c $DIR/nginx/conf/nginx.conf -p $DIR/nginx/ -g "pid $DIR/nginx/nginx.pid ; daemon off;"
fi
