# =============================================================================
# SPARK + ICEBERG + JUPYTER DOCKER IMAGE
# =============================================================================
#
# This Dockerfile creates a comprehensive analytics environment that includes:
# - Apache Spark 3.5.6 with Iceberg support
# - Jupyter Notebook with custom SQL magic commands
# - Multi-architecture support (ARM64/x86_64) with automatic detection
# - S3FileIO libraries for MinIO integration
# - Python and Scala kernels for data analysis
#
# ARCHITECTURE DECISIONS:
# - Multi-architecture support with automatic platform detection
# - Specific version pinning for reproducible builds
# - Multi-layer optimization for Docker build caching
# - Custom startup scripts for seamless notebook experience
#
# =============================================================================

# syntax=docker/dockerfile:1

# Use Python 3.10 on Debian Bullseye for stability and multi-arch support
# Bullseye provides better package availability across architectures than Alpine
FROM python:3.10-bullseye

# =============================================================================
# BUILD-TIME CONFIGURATION
# =============================================================================
# Version pinning ensures reproducible builds and compatibility

# Spark version - latest stable with Iceberg 1.6.x compatibility
ARG SPARK_VERSION=3.5.6
ARG SPARK_MAJOR_VERSION=3.5

# Iceberg version - provides mature REST catalog and S3FileIO support
ARG ICEBERG_VERSION=1.6.0

# AWS CLI version - automatically detects and downloads correct architecture
ARG AWS_CLI_VERSION=2.15.36

# =============================================================================
# SPARK ENVIRONMENT CONFIGURATION
# =============================================================================
# These paths are used by PySpark and Jupyter kernels

ENV SPARK_HOME="/opt/spark"
# Configure Python path for PySpark integration
ENV PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.9.7-src.zip:$PYTHONPATH
# Add Spark binaries to system PATH
ENV PATH="/opt/spark/sbin:/opt/spark/bin:${PATH}"
# Java classpath for IJava kernel - includes all Spark and Iceberg JARs
ENV IJAVA_CLASSPATH=/opt/spark/jars/*

# =============================================================================
# SYSTEM DEPENDENCIES AND BASE PACKAGES
# =============================================================================
# Install essential tools and Java for Spark operation

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      sudo \
      curl \
      vim \
      unzip \
      openjdk-11-jdk \
      build-essential \
      software-properties-common \
      ssh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# =============================================================================
# SPARK AND ICEBERG INSTALLATION
# =============================================================================
# Download and configure Spark with Iceberg integration libraries

RUN mkdir -p ${SPARK_HOME} && \
    # Download Spark binary distribution with Hadoop 3 support
    curl -fsSL https://dlcdn.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz -o spark.tgz && \
    tar -xzf spark.tgz --directory ${SPARK_HOME} --strip-components 1 && \
    rm spark.tgz && \
    curl -fsSL https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-${SPARK_MAJOR_VERSION}_2.12/${ICEBERG_VERSION}/iceberg-spark-runtime-${SPARK_MAJOR_VERSION}_2.12-${ICEBERG_VERSION}.jar -o ${SPARK_HOME}/jars/iceberg-spark-runtime-${SPARK_MAJOR_VERSION}_2.12-${ICEBERG_VERSION}.jar && \
    curl -fsSL https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws-bundle/${ICEBERG_VERSION}/iceberg-aws-bundle-${ICEBERG_VERSION}.jar -o ${SPARK_HOME}/jars/iceberg-aws-bundle-${ICEBERG_VERSION}.jar && \
    curl -fsSL https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-gcp-bundle/${ICEBERG_VERSION}/iceberg-gcp-bundle-${ICEBERG_VERSION}.jar -o ${SPARK_HOME}/jars/iceberg-gcp-bundle-${ICEBERG_VERSION}.jar && \
    curl -fsSL https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-azure-bundle/${ICEBERG_VERSION}/iceberg-azure-bundle-${ICEBERG_VERSION}.jar -o ${SPARK_HOME}/jars/iceberg-azure-bundle-${ICEBERG_VERSION}.jar && \
    # Auto-detect architecture for AWS CLI download
    ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then AWS_ARCH="x86_64"; else AWS_ARCH="aarch64"; fi && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}-${AWS_CLI_VERSION}.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip

# Install Python dependencies
COPY requirements.txt .
RUN pip3 install -r requirements.txt

# Install spylon kernel for Scala
RUN python3 -m spylon_kernel install

# Install IJava Jupyter kernel
RUN curl -fsSL https://github.com/SpencerPark/IJava/releases/download/v1.3.0/ijava-1.3.0.zip -o ijava-1.3.0.zip && \
    unzip ijava-1.3.0.zip && \
    python3 install.py --sys-prefix && \
    rm ijava-1.3.0.zip

# Prepare working directories
RUN mkdir -p /home/iceberg/localwarehouse /home/iceberg/notebooks /home/iceberg/warehouse /home/iceberg/spark-events /home/iceberg

# Copy notebooks and config files
COPY notebooks/ /home/iceberg/notebooks
RUN mkdir -p /root/.ipython/profile_default/startup
COPY ipython/startup/00-sql-magic.py /root/.ipython/profile_default/startup/
COPY spark-defaults.conf /opt/spark/conf
COPY .pyiceberg.yaml /root/.pyiceberg.yaml
COPY entrypoint.sh .

# Jupyter notebook startup script
RUN echo '#! /bin/sh' > /bin/notebook && \
    echo 'export PYSPARK_DRIVER_PYTHON=jupyter-notebook' >> /bin/notebook && \
    echo "export PYSPARK_DRIVER_PYTHON_OPTS=\"--notebook-dir=/home/iceberg/notebooks --ip='*' --NotebookApp.token='' --NotebookApp.password='' --port=8888 --no-browser --allow-root\"" >> /bin/notebook && \
    echo "pyspark" >> /bin/notebook && \
    chmod u+x /bin/notebook

# Set Spark binaries as executable
RUN chmod u+x /opt/spark/sbin/* && chmod u+x /opt/spark/bin/*

ENTRYPOINT ["./entrypoint.sh"]
CMD ["notebook"]

