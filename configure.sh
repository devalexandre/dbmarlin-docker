#!/bin/bash

Cyan='\033[0;36m'
Red='\033[0;31m'
Reset='\033[0m'

if (( $EUID == 0 )); then
  "Please don't run as root. We recommend you create a dbmarlin user."
  exit
fi

DIR="$(cd "$(dirname "$0")" && pwd)"

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$DIR/lib:$DIR/postgresql/lib

usage () {
  echo "./configure.sh -a [accept-eula] -t [tomcat-port] -p [postgres-port] -n [nginx-port] -s [profile-size] -u [unattended-mode] -h [help]"
  exit
}

while getopts a:t:p:n:s:u:h option
do
case "${option}"
in
a) ACCEPT_EULA=1;;
t) TOMCAT_PORT="${OPTARG}";;
p) POSTGRES_PORT="${OPTARG}";;
n) NGINX_PORT="${OPTARG}";;
s) PROFILE_SIZE="${OPTARG}";;
u) UNATTENDED_MODE=1;;
h) HELP=1;;
esac
done

if [[ ! -z "$HELP" ]]; then
    usage
fi

isRunning=`./status.sh | grep Not | wc -l`
if ! [ $isRunning -ge 3 ] ; then
  printf "${Red}DBmarlin is running${Reset}. Please run ${Cyan}stop.sh${Reset} before running ${Cyan}configure.sh${Reset}\n"
  exit
fi

echo "Starting DBmarlin configuration..."

if [[ -z  "$ACCEPT_EULA" ]]; then

  while true
  do
    read -p "Press Enter then space bar to scroll" answer

    case $answer in
    * )     more LICENSE
            break
    esac
  done

  while true
  do
    read -p "Do you accept the agreement Y/N ? " answer

    case $answer in
    [yY]* ) echo $'\n'
            echo "Continuing...."
            break;;

    [nN]* ) echo "Ok exiting"
            exit;;

    * )     echo "Please enter Y or N";;
    esac
  done
else
  echo "EULA accepted. To read in full see LICENSE"
fi

# Version to integer is needed as you can compare floats in bash
function version_to_integer {
 version=`echo "${@//v}"` # remove leading v if there is one
 version=`echo $version | sed 's/\./_/g'`
 echo $version | awk -F "_" '{ printf("%03d%03d", $1,$2); }'; # convert to int e.g. 1_2 becomes 001002
}

function get_postgres_parm {
 confline=`grep "${@} =" $DIR/postgresql/data/postgresql.conf`
 IFS=' '
 read -ra ARR <<< "$confline"
 value="${ARR[2]}"
 IFS='#'
 read -ra ARR <<< "$value"
 echo "${ARR[0]}" | tr -d '[:space:]'
}

# Takes 3 params the param_name, old_value and new_value
function set_postgres_parm {
 if [ -z "$1" ] ; then echo "Error param1 is empty"
 fi
 if [ -z "$2" ] ; then echo "Error param2 is empty"
 fi
 if [ -z "$3" ] ; then echo "Error param3 is empty"
 fi
 sed -ri "s|$1 = $2|$1 = $3|g" $DIR/postgresql/data/postgresql.conf

 echo "Changing postgresql.conf parameter ${1} from ${2} to ${3}"
}

function toggle_postgres_parm {
 if [ -z "$1" ] ; then echo "Error param1 is empty"
 fi
 if [ -z "$2" ] ; then echo "Error param2 is empty"
 fi
 if [ "$2" == "true" ] ; then
  	echo "uncommenting postgresql.conf parameter ${1}"
	sed -ri s/^\#$1/$1/g $DIR/postgresql/data/postgresql.conf
 elif [ "$2" == "false" ] ; then
	echo "commenting out postgresql.conf parameter ${1}"
	sed -ri s/^$1/\#$1/g $DIR/postgresql/data/postgresql.conf
 else
	echo "Error param2 is invalid"
 fi
}

function set_postgresql_port_in_tomcat {
  sed -ri s/"$1"/"$2"/g $DIR/tomcat/webapps/archiver##${requiredversion}/META-INF/context.xml
}

function set_postgresql_parameters {
  LocaleNew="'$locale'"
  PostgresSharedBuffersOld=$(get_postgres_parm "shared_buffers")
  LcMessagesOld="$(get_postgres_parm "lc_messages")"
  LcMonetaryOld="$(get_postgres_parm "lc_monetary")"
  LcNumericOld="$(get_postgres_parm "lc_numeric")"
  LcTimeOld="$(get_postgres_parm "lc_time")"
  set_postgres_parm "shared_buffers" $PostgresSharedBuffersOld $PostgresSharedBuffersNew
  set_postgres_parm "lc_messages" $LcMessagesOld $LocaleNew
  set_postgres_parm "lc_monetary" $LcMonetaryOld $LocaleNew
  set_postgres_parm "lc_numeric" $LcNumericOld $LocaleNew
  set_postgres_parm "lc_time" $LcTimeOld $LocaleNew
  toggle_postgres_parm "synchronous_commit" "true"
  set_postgres_parm "synchronous_commit" "on" "off"
  toggle_postgres_parm "unix_socket_directories" "true"
  set_postgres_parm "unix_socket_directories" "'/var/run/postgresql, /tmp'" "'/tmp'"
}

function check_disk_space {
 printf "Checking for enough disk space. You need double + 10 percent during a schema upgrade.\n"
 dbmarlinused=`du -s $DIR | cut -f 1`
 printf "DBmarlin is using:\t $dbmarlinused K\n"

 filesystemfree=`df -k . | grep / | awk '{print $4}'`
 printf "Filesystem free is:\t $filesystemfree K\n"

 spacerequired=$(($dbmarlinused*110/100))
 printf "Space required is:\t $spacerequired K\n"

 if [ $spacerequired -le $filesystemfree ] ; then
   printf "Freespace is OK for schema upgrade.\n"
 else
   printf "Not enough freespace available for schema upgrade.\n"
   exit
 fi

}

function get_memory {
  # Get memory
  meminfo=`cat /proc/meminfo | grep MemTotal`
  IFS=' '
  read -ra ARR <<< "$meminfo"
  TotalRAM="${ARR[1]}"
  echo $(($TotalRAM*1024))
}
TotalRAM=$(get_memory)
TotalRAMformatted=`numfmt --to=si $TotalRAM | sed s/"M"/"MB"/g | sed s/"G"/"GB"/g`

# Set shared_buffers to quarter of RAM
PostgresSharedBuffersNew=$(($TotalRAM/4/1024/1024))
PostgresSharedBuffersNew=`printf "%.0fMB\n" $PostgresSharedBuffersNew`

function get_nginx_port {
  # Get current Nginx port
  confline=`grep listen ./nginx/conf/nginx.conf`
  IFS=' '
  read -ra ARR <<< "$confline"
  IFS='='
  echo "${ARR[1]//;}"
}
NginxPortOld=$(get_nginx_port)

function get_tomcat_port {
  # Get current Tomcat port
  confline=`grep "<Connector port" tomcat/conf/server.xml | grep "HTTP/1.1"`
  IFS=' '
  read -ra ARR <<< "$confline"
  IFS='"'
  read -ra ARR <<< "${ARR[1]}"
  echo "${ARR[1]}"
}
TomcatPortOld=$(get_tomcat_port)

function get_postgresql_port {
  # Get current PostgreSQL port
  if [[ -f "postgresql/data/postgresql.conf" ]]
  then
    confline=`grep -E "^#?port" postgresql/data/postgresql.conf`
    IFS=' '
    read -ra ARR <<< "$confline"
    IFS='	'
    read -ra ARR <<< "${ARR[2]}"
    echo "${ARR[0]}"
  else
    echo "9070"
  fi
}
PostgresPortOld=$(get_postgresql_port)

function file_cleanup {
  printf "Listing files which aren't in the manifest.txt\n"

  find . -type f | sort -f  > currentfiles.txt

  diff currentfiles.txt manifest.txt | grep "^< " | sed 's/^< //' | grep "^./www/" > deletefiles.txt
  diff currentfiles.txt manifest.txt | grep "^< " | sed 's/^< //' | grep "^./tomcat/webapps/" >> deletefiles.txt

  cat deletefiles.txt | while read line
  do
    echo "Deleting $line"
    rm -rf $DIR/$line
  done

  rm deletefiles.txt currentfiles.txt

}



# Get system locale
locale=`locale | grep "LANG"`
IFS='='
read -ra ARR <<< "$locale"
locale="${ARR[1]}"

# Get required schema version
requiredversion=`grep schema-version version.txt`
IFS='='
read -ra ARR <<< "$requiredversion"
requiredversion="${ARR[1]}"
requiredschemaversion=`echo $requiredversion | sed 's/\./_/g'` # Change dot to underscore to match postgres naming

# Get user input

if [[ ! -z  "$NGINX_PORT" ]]; then
  NginxPort=$NGINX_PORT
  echo "NginxPort is $NginxPort"
  if ! [[ $NginxPort =~ $re ]] ; then
     echo "error: Not a valid port number"
     exit 1
  else
    if [ "$NginxPort" -ge 1024 ] && [ "$NginxPort" -le 65535 ] ; then
       portUsed=`netstat -nal | grep LISTEN | grep :$NginxPort | wc -l`
       if [ $portUsed -eq 1 ] ; then
         echo "Port $NginxPort already in use. If it is DBmarlin then run stop.sh first before configure.sh"
         exit 1
       fi
    else
       echo "Valid port range is 1024-65535"
    fi
  fi
else
  while true
  do
    read -p "Set port for Nginx (current $NginxPortOld): " NginxPort
    re='^[0-9]+$'
    if [[ -z "$NginxPort" ]]; then
      NginxPort=$NginxPortOld
    fi
    if ! [[ $NginxPort =~ $re ]] ; then
      echo "error: Not a valid port number"
    else
      if [ "$NginxPort" -ge 1024 ] && [ "$NginxPort" -le 65535 ] ; then
        portUsed=`netstat -nal | grep LISTEN | grep :$NginxPort | wc -l`
        if [ $portUsed -eq 1 ] ; then
          echo "Port $NginxPort already in use. If it is DBmarlin then run stop.sh first before configure.sh"
        else
          break
        fi
      else
        echo "Valid port range is 1024-65535"
      fi
    fi
  done
fi

if [[ ! -z  "$TOMCAT_PORT" ]]; then
  TomcatPort=$TOMCAT_PORT
  echo "TomcatPort is $TomcatPort"
  if ! [[ $TomcatPort =~ $re ]] ; then
     echo "error: Not a valid port number"
     exit 1
  else
    if [ "$TomcatPort" -ge 1024 ] && [ "$TomcatPort" -le 65535 ] ; then
       portUsed=`netstat -nal | grep LISTEN | grep :$TomcatPort | wc -l`
       if [ $portUsed -eq 1 ] ; then
         echo "Port $TomcatPort already in use. If it is DBmarlin then run stop.sh first before configure.sh"
         exit 1
       fi
    else
       echo "Valid port range is 1024-65535"
    fi
  fi
else
  while true
  do
    read -p "Set port for Tomcat (current $TomcatPortOld): " TomcatPort
    if [[ -z "$TomcatPort" ]]; then
      TomcatPort=$TomcatPortOld
    fi
    re='^[0-9]+$'
    if ! [[ $TomcatPort =~ $re ]] ; then
      echo "error: Not a valid port number"
    else
      if [ "$TomcatPort" -ge 1024 ] && [ "$TomcatPort" -le 65535 ] ; then
        portUsed=`netstat -nal | grep LISTEN | grep :$TomcatPort | wc -l`
        if [ $portUsed -eq 1 ] ; then
          echo "Port $TomcatPort already in use. If it is DBmarlin then run stop.sh first before configure.sh"
        else
          break
        fi
      else
        echo "Valid port range is 1024-65535"
      fi
    fi
  done
fi

if [[ ! -z  "$POSTGRES_PORT" ]]; then
  PostgresPort=$POSTGRES_PORT
  echo "PostgresPort is $PostgresPort"
  if ! [[ $PostgresPort =~ $re ]] ; then
     echo "error: Not a valid port number"
     exit 1
  else
    if [ "$PostgresPort" -ge 1024 ] && [ "$PostgresPort" -le 65535 ] ; then
       portUsed=`netstat -nal | grep LISTEN | grep :$PostgresPort | wc -l`
       if [ $portUsed -eq 1 ] ; then
         echo "Port $PostgresPort already in use. If it is DBmarlin then run stop.sh first before configure.sh"
         exit 1
       fi
    else
       echo "Valid port range is 1024-65535"
    fi
  fi
else
  while true
  do
    read -p "Set port for PostgreSQL (current $PostgresPortOld): " PostgresPort
    if [[ -z "$PostgresPort" ]]; then
      PostgresPort=$PostgresPortOld
    fi
    re='^[0-9]+$'
    if ! [[ $PostgresPort =~ $re ]] ; then
      echo "error: Not a valid port number"
    else
      if [ "$PostgresPort" -ge 1024 ] && [ "$PostgresPort" -le 65535 ] ; then
        portUsed=`netstat -nal | grep LISTEN | grep :$PostgresPort | wc -l`
        if [ $portUsed -eq 1 ] ; then
          echo "Port $PostgresPort already in use. If it is DBmarlin then run stop.sh first before configure.sh"
        else
          break
        fi
      else
        echo "Valid port range is 1024-65535"
      fi
    fi
  done
fi

function list_include_item {
  local list="$1"
  local item="$2"
  if [[ $list =~ (^|[[:space:]])"$item"($|[[:space:]]) ]] ; then
    # yes, list include item
    result=0
  else
    result=1
  fi
  return $result
}

valid_profiles="XSmall Small Medium Large XLarge"

if [[ ! -z  "$PROFILE_SIZE" ]]; then
  profile=$PROFILE_SIZE
  if `list_include_item $valid_profiles $profile` ; then
    echo "profile is $profile"
  else
    echo "Profile $profile - Not a valid profile size. Valid options are: $valid_profiles"
    exit 1
  fi
else
  PS3="Choose the profile [1-5]: "

  echo "See https://docs.dbmarlin.com/docs/Getting-Started/hardware-requirements for Profile sizes"
  select profile in XSmall Small Medium Large XLarge
  do
      case $profile in
      XSmall)
        echo "XSmall profile selected"
        echo "Recommended RAM is 1GB. You have $TotalRAMformatted"
        break
        ;;
      Small)
        echo "Small profile selected"
        echo "Recommended RAM is 4GB. You have $TotalRAMformatted"
        break
        ;;
      Medium)
        echo "Medium profile selected"
        echo "Recommended RAM is 8GB. You have $TotalRAMformatted"
        break
        ;;
      Large)
        echo "Large profile selected"
        echo "Recommended RAM is 16GB. You have $TotalRAMformatted"
        break
        ;;
      XLarge)
        echo "XLarge profile selected"
        echo "Recommended RAM is 32GB. You have $TotalRAMformatted"
        break
        ;;
      *)
        echo "Invalid option $REPLY"
        ;;
      esac
  done
fi

if [[ ! -z  "$UNATTENDED_MODE" ]]; then
  do_setup="Y"
else
  while true
  do
    read -p "Continue Y/N ? " answer

    case $answer in
    [yY]* ) echo $'\n'
            do_setup="Y"
            break;;

    [nN]* ) echo "Ok exiting"
            exit;;

    * )    echo "Please enter Y or N";;
    esac
  done
fi

if [ do_setup=="Y" ] ; then

  echo "Configuring DBmarlin now..."

  echo Changing Nginx port from $NginxPortOld to $NginxPort
  sed -ri s/"$NginxPortOld"/"$NginxPort"/g ./nginx/conf/nginx.conf

  echo Changing Tomcat port from $TomcatPortOld to $TomcatPort
  sed -ri s/"$TomcatPortOld"/"$TomcatPort"/g ./tomcat/conf/server.xml
  sed -ri s/"$TomcatPortOld"/"$TomcatPort"/g ./nginx/conf/shared.conf
  sed -ri s/"$TomcatPortOld"/"$TomcatPort"/g ./tomcat/webapps/agent##${requiredversion}/META-INF/context.xml

  echo "Using profile $profile"

  if [ ! -d $DIR/postgresql/data ]
  then
    echo "New installation; Create database needed"
    # Initialize a new PostgreSQL instance and add timescaledb extension
    cd "$DIR/postgresql"
    bin/initdb -D $DIR/postgresql/data -E 'UTF-8' --locale=$locale -U postgres
    echo "shared_preload_libraries = 'timescaledb,pg_stat_statements'" >> $DIR/postgresql/data/postgresql.conf

    set_postgresql_parameters

    toggle_postgres_parm "port" "true"
    set_postgres_parm "port" "5432" "$PostgresPort" # Since the PostgreSQL is only created here during install the port is 5432
    set_postgresql_port_in_tomcat  "9070" "$PostgresPort" # We ship with default PostgreSQL port set to 9070 on Tomcat side

    # Run schema creation scripts
    cd ..
    ./start.sh -p
    cd "$DIR/postgresql/sql"
    export PATH=$PATH:$DIR/postgresql/bin/
    which psql
      echo "CONNECTING to psql on port $PostgresPort"
      #psql -p $PostgresPort postgres -h /tmp -f create_root_schema.sql
    ./build-root.sh $PostgresPort
    ./build.sh $PostgresPort
    ./build-hypertables.sh $PostgresPort
    cd ../..
    ./stop.sh -p
  else
    printf "${Red}Existing postgres database detected. Checking the schema version to see if upgrade is required.${Reset}\n"

    set_postgresql_parameters

    echo Changing PostgreSQL port from $PostgresPortOld to $PostgresPort
    toggle_postgres_parm "port" "true"
    set_postgres_parm "port" "$PostgresPortOld" "$PostgresPort"
    set_postgresql_port_in_tomcat  "9070" "$PostgresPort" # We ship with default PostgreSQL port set to 9070 on Tomcat side
    set_postgresql_port_in_tomcat  "$PostgresPortOld" "$PostgresPort" # If you run configure.sh again then it won't be 9070

    printf "PostgreSQL ${Cyan}starting up${Reset}\n"
    ./start.sh -p
    export PATH=$PATH:$DIR/postgresql/bin
    echo "ALTER role dbmarlin with superuser" | psql -p $PostgresPort -h /tmp -U postgres -d template1
    echo "ALTER EXTENSION timescaledb UPDATE" | psql -p $PostgresPort -h /tmp -U dbmarlin
    timescaleversion=`echo "\dx timescaledb" | psql -p $PostgresPort -h /tmp -U dbmarlin`
    echo $timescaleversion
    schemaversions=`echo "\dn" | psql -p $PostgresPort -h /tmp -U dbmarlin | grep -o 'v[[:digit:]]*_[[:digit:]]' | sort`
    echo "Detected the following schema versions:"
    echo $schemaversions
    schemaversions=`echo "${schemaversions//v}"` # Strip to leading v for easier comparison
    numschemas=`echo -n "$schemaversions" | grep -c '^'`
    latestschema=`echo -n "$schemaversions" | tail -1`

    printf "Set default schema to ${Cyan}v$requiredschemaversion${Reset}\n"
    echo "alter role dbmarlin in database dbmarlin set search_path = 'v$requiredschemaversion';" | psql -p $PostgresPort -h /tmp -U dbmarlin

    if [ "$(version_to_integer $latestschema)" -gt "$(version_to_integer $requiredschemaversion)" ];then
      printf "Current schema version ${Cyan}$latestschema${Reset} is greater than required version ${Cyan}$requiredschemaversion${Reset}\n"
      printf "${Red}You have a more recent schema version installed than this software installation requires. You may need to download a newer version of software which is compatible with the schema${Reset}\n"
      echo "Exiting"
      exit
    elif [ "$(version_to_integer $latestschema)" -lt "$(version_to_integer $requiredschemaversion)" ]; then
      check_disk_space
      printf "Current schema ${Cyan}$latestschema${Reset} is less than required version ${Cyan}$requiredschemaversion${Reset}\n"
      printf "Will create the new ${Cyan}$requiredschemaversion${Reset} schema now.\n"
      cd "$DIR/postgresql/sql"
      ./build.sh $PostgresPort
      ./build-hypertables.sh $PostgresPort
      cd ../..
      printf "Data will copy from the old ${Cyan}$latestschema${Reset} schema to the new ${Cyan}$requiredschemaversion${Reset} schema now.\n"
      printf "${Red}Please be patient. It could take over 20 mins depending on your database size. Please let it complete to avoid leaving your database in an inconsistent state.${Reset}\n"
      ./tomcat/bin/migrate.sh ${requiredversion}

    elif [ "$(version_to_integer $latestschema)" -eq "$(version_to_integer $requiredschemaversion)" ]; then
      printf "You have the latest schema already. No schema update necessary.\n"
    else
      printf "${Red}Something went wrong. Please contact support${Reset}\n"
      echo "Exiting"
      exit
    fi

    ./stop.sh -p

    # Compare files to those in manifest.txt and clean up redundant files
    file_cleanup


    if [ $numschemas -ge 2 ]
    then
      printf "You have $numschemas schemas\n"
      printf "Latest installed schema is ${Cyan}$latestschema${Reset}\n"
      printf "Required schema is ${Cyan}$requiredschemaversion${Reset}\n"
      printf "${Red}Is an upgrade already in progress?${Reset}\n"
        echo "Exiting"
      exit
    fi
  fi

  echo "All done!"
  printf "Next run ${Cyan}./start.sh${Reset} to startup the DBmarlin services\n"
  printf "Then connect to ${Cyan}http://`hostname | tr -d '[:space:]'`:$NginxPort/${Reset} in your browser\n"


else
    echo "Aborting setup"
    exit
fi
