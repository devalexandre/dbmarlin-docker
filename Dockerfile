FROM centos:centos7

WORKDIR /opt

RUN useradd dbmarlin 
RUN mkdir /opt/dbmarlin
# Set the locale
RUN localedef -i pt_BR -f UTF-8 pt_BR.UTF-8

RUN yum install -y procps net-tools tar hostname



RUN curl https://download.dbmarlin.com/dbmarlin-Linux-x64-2.5.0.tar.gz --output dbmarlin-Linux-x64-2.5.0.tar.gz
RUN tar -xzvf dbmarlin-Linux-x64-2.5.0.tar.gz 

RUN chown -R dbmarlin:dbmarlin dbmarlin
COPY configure.sh dbmarlin/configure.sh

USER dbmarlin 
WORKDIR /opt/dbmarlin
RUN ./configure.sh -a True -t 9080 -p 9070 -n 9090 -s XSmall -u True
RUN ./start.sh 

EXPOSE 9090
EXPOSE 9080
EXPOSE 9070


