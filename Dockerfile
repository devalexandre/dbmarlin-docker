FROM centos:centos7

WORKDIR /home/app

RUN useradd dbmarlin 

# Set the locale
RUN localedef -i pt_BR -f UTF-8 pt_BR.UTF-8

RUN yum install net-tools -y

RUN curl https://download.dbmarlin.com/dbmarlin-Linux-x64-2.5.0.tar.gz\?_ga\=2.61122860.1048656673.1654988646-192707094.1654988646 --output dbmarlin-Linux-x64-2.5.0.tar.gz
RUN tar -xzvf dbmarlin-Linux-x64-2.5.0.tar.gz 

RUN chown dbmarlin:dbmarlin /home/app/dbmarlin

COPY configure.sh /home/app/dbmarlin/configure.sh

RUN chmod 777 -R /home/app/dbmarlin
USER dbmarlin 

EXPOSE 9090
EXPOSE 9080
EXPOSE 9070

RUN cd /home/app/dbmarlin && ./configure.sh -a yes -t 9080 -p 9070 -n 9090 -s Small -u yes

CMD "cd /home/app/dbmarlin && ./start.sh -tpn"
 