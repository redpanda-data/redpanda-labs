# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# syntax=docker/dockerfile:1
FROM python:3.10-bullseye

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

# Set environment variables
ENV SPARK_HOME="/opt/spark"
ENV SPARK_VERSION=3.5.7
ENV SPARK_MAJOR_VERSION=3.5
ENV ICEBERG_VERSION=1.6.0
ENV PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.9.7-src.zip

# Download and extract Spark, and download Iceberg JARs and AWS CLI
RUN mkdir -p ${SPARK_HOME} && \
    curl -fsSL https://dlcdn.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz -o spark.tgz && \
    tar -xzf spark.tgz --directory ${SPARK_HOME} --strip-components 1 && \
    rm spark.tgz && \
    curl -fsSL https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-${SPARK_MAJOR_VERSION}_2.12/${ICEBERG_VERSION}/iceberg-spark-runtime-${SPARK_MAJOR_VERSION}_2.12-${ICEBERG_VERSION}.jar -o ${SPARK_HOME}/jars/iceberg-spark-runtime-${SPARK_MAJOR_VERSION}_2.12-${ICEBERG_VERSION}.jar && \
    curl -fsSL https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws-bundle/${ICEBERG_VERSION}/iceberg-aws-bundle-${ICEBERG_VERSION}.jar -o ${SPARK_HOME}/jars/iceberg-aws-bundle-${ICEBERG_VERSION}.jar && \
    curl -fsSL https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-gcp-bundle/${ICEBERG_VERSION}/iceberg-gcp-bundle-${ICEBERG_VERSION}.jar -o ${SPARK_HOME}/jars/iceberg-gcp-bundle-${ICEBERG_VERSION}.jar && \
    curl -fsSL https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-azure-bundle/${ICEBERG_VERSION}/iceberg-azure-bundle-${ICEBERG_VERSION}.jar -o ${SPARK_HOME}/jars/iceberg-azure-bundle-${ICEBERG_VERSION}.jar && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    sudo ./aws/install && \
    rm awscliv2.zip && rm -rf aws/

# Download datasets early for caching
RUN mkdir -p /home/iceberg/data && \
    curl -fsSL https://data.cityofnewyork.us/resource/tg4x-b46p.json -o /home/iceberg/data/nyc_film_permits.json && \
    curl -fsSL https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-04.parquet -o /home/iceberg/data/yellow_tripdata_2022-04.parquet && \
    curl -fsSL https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-03.parquet -o /home/iceberg/data/yellow_tripdata_2022-03.parquet && \
    curl -fsSL https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-02.parquet -o /home/iceberg/data/yellow_tripdata_2022-02.parquet && \
    curl -fsSL https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-01.parquet -o /home/iceberg/data/yellow_tripdata_2022-01.parquet && \
    curl -fsSL https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-12.parquet -o /home/iceberg/data/yellow_tripdata_2021-12.parquet && \
    curl -fsSL https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-11.parquet -o /home/iceberg/data/yellow_tripdata_2021-11.parquet && \
    curl -fsSL https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-10.parquet -o /home/iceberg/data/yellow_tripdata_2021-10.parquet && \
    curl -fsSL https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-09.parquet -o /home/iceberg/data/yellow_tripdata_2021-09.parquet && \
    curl -fsSL https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-08.parquet -o /home/iceberg/data/yellow_tripdata_2021-08.parquet && \
    curl -fsSL https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-07.parquet -o /home/iceberg/data/yellow_tripdata_2021-07.parquet && \
    curl -fsSL https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-06.parquet -o /home/iceberg/data/yellow_tripdata_2021-06.parquet && \
    curl -fsSL https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-05.parquet -o /home/iceberg/data/yellow_tripdata_2021-05.parquet && \
    curl -fsSL https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-04.parquet -o /home/iceberg/data/yellow_tripdata_2021-04.parquet

# Prepare directories
RUN mkdir -p /home/iceberg/localwarehouse /home/iceberg/notebooks /home/iceberg/warehouse /home/iceberg/spark-events /home/iceberg

# Install Python dependencies
COPY requirements.txt .
RUN pip3 install -r requirements.txt

# Install spylon-kernel for Scala
RUN python3 -m spylon_kernel install

# Install IJava Jupyter kernel
RUN curl -fsSL https://github.com/SpencerPark/IJava/releases/download/v1.3.0/ijava-1.3.0.zip -o ijava-1.3.0.zip && \
    unzip ijava-1.3.0.zip && \
    python3 install.py --sys-prefix && \
    rm ijava-1.3.0.zip

# Add iceberg spark runtime jar to IJava classpath
ENV IJAVA_CLASSPATH=/opt/spark/jars/*

# Copy notebooks and configuration files
COPY notebooks/ /home/iceberg/notebooks
COPY ipython/startup/00-prettytables.py /root/.ipython/profile_default/startup
COPY ipython/startup/README /root/.ipython/profile_default/startup
COPY spark-defaults.conf /opt/spark/conf
COPY .pyiceberg.yaml /root/.pyiceberg.yaml
COPY entrypoint.sh .

# Add notebook and pyspark-notebook commands
RUN echo '#! /bin/sh' > /bin/notebook && \
    echo 'export PYSPARK_DRIVER_PYTHON=jupyter-notebook' >> /bin/notebook && \
    echo "export PYSPARK_DRIVER_PYTHON_OPTS=\"--notebook-dir=/home/iceberg/notebooks --ip='*' --NotebookApp.token='' --NotebookApp.password='' --port=8888 --no-browser --allow-root\"" >> /bin/notebook && \
    echo "pyspark" >> /bin/notebook && \
    chmod u+x /bin/notebook && \
    echo '#! /bin/sh' > /bin/pyspark-notebook && \
    echo 'export PYSPARK_DRIVER_PYTHON=jupyter-notebook' >> /bin/pyspark-notebook && \
    echo "export PYSPARK_DRIVER_PYTHON_OPTS=\"--notebook-dir=/home/iceberg/notebooks --ip='*' --NotebookApp.token='' --NotebookApp.password='' --port=8888 --no-browser --allow-root\"" >> /bin/pyspark-notebook && \
    echo "pyspark" >> /bin/pyspark-notebook && \
    chmod u+x /bin/pyspark-notebook

# Set Spark binaries as executable
RUN chmod u+x /opt/spark/sbin/* && \
    chmod u+x /opt/spark/bin/*

ENV PATH="/opt/spark/sbin:/opt/spark/bin:${PATH}"

ENTRYPOINT ["./entrypoint.sh"]
CMD ["notebook"]

