FROM archlinux:latest

WORKDIR /home/app

RUN useradd dbmarlin 

RUN curl https://download.dbmarlin.com/dbmarlin-Linux-x64-2.5.0.tar.gz\?_ga\=2.61122860.1048656673.1654988646-192707094.1654988646 --output dbmarlin-Linux-x64-2.5.0.tar.gz
RUN tar -xzvf dbmarlin-Linux-x64-2.5.0.tar.gz 

RUN chown dbmarlin:dbmarlin /home/app/dbmarlin

RUN chmod 777 -R /home/app/dbmarlin
COPY configure.sh  /home/app/dbmarlin/configure.sh 

USER dbmarlin 
WORKDIR /home/app/dbmarlin
RUN ./configure.sh -a True -n 9090 -t 9080 -p 9070 -s Small -u True

EXPOSE 9090
EXPOSE 9080
EXPOSE 9070


CMD "./start.sh -tpn"
