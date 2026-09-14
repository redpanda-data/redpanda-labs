# Apache Spark with the two Iceberg jars, and nothing else.
#
# The Redpanda Labs Iceberg lab this solution replaces built a 4 GB image:
# Spark from source, Jupyter, four language kernels, the AWS CLI, and 14
# sample Parquet datasets downloaded at build time. None of that is needed to
# run a SQL query, so this image is the official Spark image plus
# iceberg-spark-runtime (the Iceberg SQL extensions and catalog) and
# iceberg-aws-bundle (the S3 file IO that talks to MinIO). It builds in under
# a minute and adds about 60 MB to the base image.
ARG SPARK_VERSION=3.5.7
FROM apache/spark:${SPARK_VERSION}

ARG SPARK_VERSION=3.5.7
ARG ICEBERG_SPARK_VERSION=1.6.0
# The Iceberg runtime is published per Spark minor version, so 3.5.7 takes the
# 3.5 artifact.
ARG SPARK_MAJOR_VERSION=3.5
ARG SCALA_VERSION=2.12

USER root

RUN set -eu; \
    base=https://repo1.maven.org/maven2/org/apache/iceberg; \
    curl -fsSL "$base/iceberg-spark-runtime-${SPARK_MAJOR_VERSION}_${SCALA_VERSION}/${ICEBERG_SPARK_VERSION}/iceberg-spark-runtime-${SPARK_MAJOR_VERSION}_${SCALA_VERSION}-${ICEBERG_SPARK_VERSION}.jar" \
      -o /opt/spark/jars/iceberg-spark-runtime.jar; \
    curl -fsSL "$base/iceberg-aws-bundle/${ICEBERG_SPARK_VERSION}/iceberg-aws-bundle-${ICEBERG_SPARK_VERSION}.jar" \
      -o /opt/spark/jars/iceberg-aws-bundle.jar

COPY spark-defaults.conf /opt/spark/conf/spark-defaults.conf

USER spark

ENV PATH="/opt/spark/bin:/opt/spark/sbin:${PATH}"
