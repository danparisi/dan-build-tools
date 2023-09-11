FROM openjdk:17 as builder
EXPOSE 8080

WORKDIR application
COPY target/*.jar target/

RUN java -Djarmode=layertools -jar target/*.jar extract --destination unpacked-with-layers


FROM amazoncorretto:17

EXPOSE 8080 5005

ENV JAVA_EXTRA_OPTS ""
ENV JAVA_OPTS "-verbose:gc \
             -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005 \
             -Dcom.sun.management.jmxremote \
             -Dcom.sun.management.jmxremote.local.only=false \
             -Dcom.sun.management.jmxremote.ssl=false \
             -Dcom.sun.management.jmxremote.authenticate=false \
             -Dcom.sun.management.jmxremote.port=9010 \
             -Dcom.sun.management.jmxremote.rmi.port=9011 \
             -Djava.rmi.server.hostname=localhost \
             -Xmx512m \
             -XX:CompressedClassSpaceSize=50m \
             -XX:-TieredCompilation"

COPY --from=builder application/unpacked-with-layers/application/ ./
COPY --from=builder application/unpacked-with-layers/dependencies/ ./
COPY --from=builder application/unpacked-with-layers/spring-boot-loader/ ./
COPY --from=builder application/unpacked-with-layers/snapshot-dependencies/ ./

ENTRYPOINT java ${JAVA_OPTS} ${JAVA_EXTRA_OPTS} org.springframework.boot.loader.JarLauncher