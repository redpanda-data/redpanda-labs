#!/bin/bash

filename="$1"
topic="$2"

if [[ -z "$filename" || -z "$topic" ]]; then
    echo "Usage: $0 <filename> <topic>"
    exit 1
fi

{
    read # Skip the header row
    while IFS= read -r line; do
        echo "$line" | rpk topic produce "$topic"
    done
} < "$filename"
