# Builds a Kroxylicious proxy image with the demo's custom "topic-prefixer" filter added to its
# classpath, via the "classpath-plugins" extension point (see kroxylicious-app's proxy.dockerfile /
# kroxylicious-start.sh). See ../README.adoc for why this lab needs a custom filter at all.
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build
COPY pom.xml .
COPY src ./src
RUN mvn -B -q package -DskipTests

FROM quay.io/kroxylicious/proxy:0.24.0
COPY --from=build /build/target/topic-prefixer.jar /opt/kroxylicious/classpath-plugins/topic-prefixer/topic-prefixer.jar
