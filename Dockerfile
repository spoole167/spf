FROM ubuntu:16.04
RUN apt-get update &&  \
    apt-get -y install curl jq unzip bc vim

#directories to hold the app servers
RUN mkdir -p /spf/servers
RUN mkdir -p /spf/servers/tomcat
RUN mkdir -p /spf/servers/jetty

#directories to hold the runtimes
RUN mkdir -p /spf/runtimes/java/9
RUN mkdir -p /spf/runtimes/java/8

# directories and files to be mounts
RUN mkdir -p /spf/results
RUN mkdir -p /spf/tmp
RUN mkdir -p /spf/app
RUN touch /spf/app/app.war

#
# get ngrinder 3.4.1

#
# Create a default webapp direectory and install ngrinder
#
RUN curl -L -o /spf/app/app.war  https://github.com/naver/ngrinder/releases/download/ngrinder-3.4.1-20170131/ngrinder-controller-3.4.1.war

#
# Get latest build info from adoptopenjdk site
# Download binary and expand to have a standard vm oriented name
#

# Get OpenJDK with Hotspot

RUN  export RELEASE_NAME=`curl -s -H 'accept-version: 1.0.0' https://api.adoptopenjdk.net/openjdk9/releases/x64_linux | jq  -r '.release_name'` && \
     export BIN_LINK=`curl -s -H 'accept-version: 1.0.0' https://api.adoptopenjdk.net/openjdk9/releases/x64_linux | jq -r '.binaries[0].binary_link'` && \
     curl -L  -o openjdk9-hotspot-javabin.tar.gz  $BIN_LINK &&  \
     gunzip openjdk9-hotspot-javabin.tar.gz  && \
     tar -xf openjdk9-hotspot-javabin.tar && \
     mv $RELEASE_NAME  /spf/runtimes/java/9/hotspot && \
     rm openjdk9-hotspot-javabin.tar


# Get OpenJDK with OpenJ9

RUN  export RELEASE_NAME=`curl -s -H 'accept-version: 1.0.0' https://api.adoptopenjdk.net/openjdk9-openj9/releases/x64_linux | jq  -r '.release_name'` && \
     export BIN_LINK=`curl -s -H 'accept-version: 1.0.0' https://api.adoptopenjdk.net/openjdk9-openj9/releases/x64_linux | jq -r '.binaries[0].binary_link'` && \
     curl -L  -o openjdk9-openj9-javabin.tar.gz  $BIN_LINK &&  \
     gunzip openjdk9-openj9-javabin.tar.gz  && \
     tar -xf openjdk9-openj9-javabin.tar && \
     mv $RELEASE_NAME  /spf/runtimes/java/9/openj9 && \
     rm openjdk9-openj9-javabin.tar


# Get OpenJDK with OpenJ9

RUN  export RELEASE_NAME=`curl -s -H 'accept-version: 1.0.0' https://api.adoptopenjdk.net/openjdk8/releases/x64_linux | jq  -r '.[0].release_name'` && \
          export BIN_LINK=`curl -s -H 'accept-version: 1.0.0' https://api.adoptopenjdk.net/openjdk8/releases/x64_linux | jq -r '.[0].binaries[0].binary_link'` && \
          echo $BIN_LINK && \
          curl -L  -o openjdk8-hotspot-javabin.tar.gz  $BIN_LINK &&  \
          gunzip openjdk8-hotspot-javabin.tar.gz  && \
          tar -xf openjdk8-hotspot-javabin.tar && \
          mv $RELEASE_NAME  /spf/runtimes/java/8/hotspot && \
          rm openjdk8-hotspot-javabin.tar

# Get OpenJDK with OpenJ9

RUN  export RELEASE_NAME=`curl -s -H 'accept-version: 1.0.0' https://api.adoptopenjdk.net/openjdk8-openj9/releases/x64_linux | jq  -r '.release_name'` && \
          export BIN_LINK=`curl -s -H 'accept-version: 1.0.0' https://api.adoptopenjdk.net/openjdk8-openj9/releases/x64_linux | jq -r '.binaries[0].binary_link'` && \
        echo $BIN_LINK && \
          curl -L  -o openjdk8-openj9-javabin.tar.gz  $BIN_LINK &&  \
          gunzip openjdk8-openj9-javabin.tar.gz  && \
          tar -xf openjdk8-openj9-javabin.tar && \
          mv $RELEASE_NAME  /spf/runtimes/java/8/openj9 && \
          rm openjdk8-openj9-javabin.tar

#
# get servers
#

#
# get tomcat 9.05
#
RUN  curl -L -o apache-tomcat-9.0.5.tar.gz  http://mirrors.ukfast.co.uk/sites/ftp.apache.org/tomcat/tomcat-9/v9.0.5/bin/apache-tomcat-9.0.5.tar.gz && \
     gunzip  apache-tomcat-9.0.5.tar.gz  && \
     tar -xf apache-tomcat-9.0.5.tar  -C /spf/servers/tomcat --strip-components 1 && \
     rm apache-tomcat-9.0.5.tar

# clear out tomcat supplied webapps
RUN rm -rf /spf/servers/tomcat/webapps/*

#
# get jetty
#

RUN curl -L -o jetty.tar.gz  http://central.maven.org/maven2/org/eclipse/jetty/jetty-distribution/9.4.8.v20171121/jetty-distribution-9.4.8.v20171121.tar.gz && \
    gunzip  jetty.tar.gz && \
    tar -xf jetty.tar -C /spf/servers/jetty --strip-components 1  && \
    rm jetty.tar




# open some basic ports
EXPOSE 9080
EXPOSE 8080
EXPOSE 9443

RUN ln -s /spf/app/app.war  /spf/servers/tomcat/webapps/ROOT.war

RUN mkdir -p /spf/servers/jetty/webapps
RUN ln -s /spf/app/app.war  /spf/servers/jetty/webapps/root.war

#
# add launcher script
#

COPY spf_client.sh /
RUN chmod +x spf_client.sh
ENTRYPOINT ["/spf_client.sh"]
