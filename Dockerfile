FROM archlinux:base-devel

WORKDIR /home/app

RUN useradd dbmarlin 

RUN pacman -Sy inetutils libxcrypt-compat --noconfirm
RUN curl https://download.dbmarlin.com/dbmarlin-Linux-x64-2.5.0.tar.gz --output dbmarlin-Linux-x64-2.5.0.tar.gz
RUN tar -xzvf dbmarlin-Linux-x64-2.5.0.tar.gz 

RUN chown dbmarlin:dbmarlin /home/app/dbmarlin

RUN chmod 777 -R /home/app/dbmarlin
COPY configure.sh  /home/app/dbmarlin/configure.sh 
RUN rm dbmarlin-Linux-x64-2.5.0.tar.gz 
USER dbmarlin 
WORKDIR /home/app/dbmarlin
RUN ./configure.sh -a True -n 9090 -t 9080 -p 9070 -s Small -u True

EXPOSE 9090
EXPOSE 9080
EXPOSE 9070


ENTRYPOINT ["sh", "/home/app/dbmarlin/start.sh"]
