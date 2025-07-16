#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# This entrypoint starts all required Spark services for the Iceberg lab:
#
# 1. Spark Master (port 7077):
#    - Cluster resource manager for distributed computing
#    - Coordinates Spark applications and executor allocation
#    - Web UI available at http://localhost:8080 (if port-forwarded)
#
# 2. Spark Worker:
#    - Connects to master for task execution
#    - Provides compute resources for Spark SQL queries
#    - Automatically discovers master via localhost connection
#
# 3. Spark History Server:
#    - Tracks completed Spark applications and job metrics
#    - Essential for debugging and performance analysis
#    - Web UI shows execution plans and stage timings
#
# 4. Spark Thrift Server:
#    - JDBC/ODBC interface for SQL clients
#    - Enables external tools to connect to Spark SQL
#    - Derby database stores temporary metadata (dev-only)
#
# 5. Custom Command Execution:
#    - Supports additional commands (jupyter, pyspark)
#    - Maintains running services while executing user workloads
#    - Flexible entry point for different use cases
#
# Architecture: All services run in the same container for simplified deployment
# and resource sharing in the lab environment
start-master.sh -p 7077
start-worker.sh spark://localhost:7077
start-history-server.sh
start-thriftserver.sh  --driver-java-options "-Dderby.system.home=/tmp/derby"

# Entrypoint, for example notebook, pyspark or spark-sql
if [[ $# -gt 0 ]] ; then
    eval "$1"
fi
