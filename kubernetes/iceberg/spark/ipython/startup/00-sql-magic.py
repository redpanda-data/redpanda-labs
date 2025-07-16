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

"""
Custom SQL Magic for Jupyter Notebooks with Spark and Iceberg Integration

This module provides a custom %%sql magic command for Jupyter notebooks that:
1. Executes Spark SQL queries with proper formatting
2. Handles binary data common in Redpanda/Kafka message formats
3. Provides readable table output using PrettyTable
4. Supports variable assignment for DataFrames

Key Features:
- Automatic binary-to-string conversion for message keys/values
- Configurable row limits for large result sets
- HTML and text rendering for Jupyter display
- Integration with Spark DataFrames for further processing

Usage Examples:
    %%sql
    SELECT * FROM lab.redpanda.key_value LIMIT 10

    %%sql --decode key,value --limit 50 --var my_df
    SELECT partition, offset, key, value FROM lab.redpanda.key_value
"""

from prettytable import PrettyTable
from IPython.core.magic import register_line_cell_magic
from pyspark.sql.functions import col
import re
import sys
from argparse import ArgumentParser

class DFTable(PrettyTable):
    """
    Enhanced PrettyTable for DataFrame display in Jupyter notebooks.

    Provides both text and HTML representations for better Jupyter integration.
    The HTML output renders nicely in notebook cells while text output
    works in terminal environments.
    """
    def __repr__(self):
        return self.get_string()

    def _repr_html_(self):
        """Generate HTML table for rich Jupyter display"""
        return self.get_html_string()

def _row_as_table(df):
    """
    Format a single row as a transposed table (column-value pairs).

    Useful for examining individual records in detail, especially
    for wide tables with many columns like Redpanda message metadata.

    Args:
        df: Spark DataFrame

    Returns:
        DFTable: Formatted table with Column/Value layout
    """
    cols = df.columns
    t = DFTable()
    t.field_names = ["Column", "Value"]
    t.align = "r"
    row = df.limit(1).collect()[0].asDict()
    for col_name in cols:
        t.add_row([col_name, row[col_name]])
    return t

def _to_table(df, num_rows=100):
    """
    Convert Spark DataFrame to PrettyTable for display.

    Handles the conversion from Spark's internal representation to
    a human-readable table format. Limits rows to prevent overwhelming
    the notebook output.

    Args:
        df: Spark DataFrame
        num_rows: Maximum number of rows to display

    Returns:
        DFTable: Formatted table for display
    """
    cols = df.columns
    t = DFTable()
    t.field_names = cols
    t.align = "r"
    for row in df.limit(num_rows).collect():
        d = row.asDict()
        t.add_row([d[col] for col in cols])
    return t

def _decode_binary(df, binary_cols):
    """
    Convert binary columns to human-readable strings.

    Redpanda/Kafka messages often store keys and values as binary data.
    This function converts specified binary columns to UTF-8 strings
    for easier reading and analysis.

    Args:
        df: Spark DataFrame
        binary_cols: List of column names to convert from binary to string

    Returns:
        DataFrame: DataFrame with specified columns converted to strings
    """
    for colname in binary_cols:
        if colname in df.columns:
            df = df.withColumn(colname, col(colname).cast("string"))
    return df

# Command line argument parser for magic command options
parser = ArgumentParser()
parser.add_argument("--limit",
                   help="Number of rows to return (default: 100)",
                   type=int,
                   default=100)
parser.add_argument("--var",
                   help="Variable name to store the DataFrame for further processing",
                   type=str)
parser.add_argument("--decode",
                   help="Comma-separated list of binary columns to decode to string (such as key,value)",
                   type=str,
                   default="")

@register_line_cell_magic
def sql(line, cell=None):
    """
    Custom SQL magic for Spark with Iceberg integration.

    This magic command provides a seamless interface for querying Iceberg tables
    created by Redpanda. It automatically handles common data formatting issues
    and provides options for working with binary message data.

    Arguments:
        --limit N: Limit output to N rows (default: 100)
        --var VAR: Store DataFrame in variable VAR for further processing
        --decode COLS: Convert binary columns to strings (e.g., --decode key,value)

    Examples:
        # Basic query
        %%sql
        SELECT * FROM lab.redpanda.key_value

        # Decode binary data and limit results
        %%sql --decode key,value --limit 20
        SELECT partition, offset, key, value FROM lab.redpanda.key_value

        # Store result for further processing
        %%sql --var result_df
        SELECT COUNT(*) as message_count FROM lab.redpanda.key_value
    """
    from pyspark.sql import SparkSession

    # Get or create Spark session with Iceberg configuration
    # The session should already be configured via spark-defaults.conf
    spark = SparkSession.builder.appName("Jupyter").getOrCreate()

    # Use cell content if it's a cell magic, otherwise use line content
    query = cell if cell else line

    # Execute the SQL query
    df = spark.sql(query)

    # Parse command line arguments from the magic command line
    (args, others) = parser.parse_known_args([arg for arg in re.split("\\s+", line) if arg])

    # Apply binary decoding if requested
    # This is particularly useful for Redpanda message keys and values
    if args.decode:
        decode_cols = [col.strip() for col in args.decode.split(",") if col.strip()]
        if decode_cols:
            df = _decode_binary(df, decode_cols)

    # Store DataFrame in a variable if requested
    # Useful for further processing or chaining operations
    if args.var:
        setattr(sys.modules[__name__], args.var, df)

    # Format output based on limit
    # Single row gets transposed view, multiple rows get standard table
    if args.limit == 1:
        return _row_as_table(df)
    else:
        return _to_table(df, num_rows=args.limit)
