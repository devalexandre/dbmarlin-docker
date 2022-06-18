FROM ubuntu:latest

WORKDIR /home/app

ENV size=Small

RUN useradd dbmarlin 
RUN apt update -y
RUN apt-get install curl inetutils-tools locales -y 

RUN curl https://download.dbmarlin.com/dbmarlin-Linux-x64-2.5.0.tar.gz --output dbmarlin-Linux-x64-2.5.0.tar.gz
RUN tar -xzvf dbmarlin-Linux-x64-2.5.0.tar.gz 

RUN chown dbmarlin:dbmarlin /home/app/dbmarlin

RUN chmod 777 -R /home/app/dbmarlin
COPY configure.sh  /home/app/dbmarlin/configure.sh 
COPY start.sh  /home/app/dbmarlin/start.sh 

RUN rm dbmarlin-Linux-x64-2.5.0.tar.gz 


RUN ls /usr/share/i18n/locales

# Set the localevou pensar se rola separar es
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen
ENV LANG en_US.UTF-8  
ENV LANGUAGE en_US:en  
ENV LC_ALL en_US.UTF-8 


USER dbmarlin 
WORKDIR /home/app/dbmarlin
RUN ./configure.sh -a True -n 9090 -t 9080 -p 9070 -s $size -u True

EXPOSE 9070-9090

CMD ["/home/app/dbmarlin/start.sh"]