#!/bin/bash
filename="$1"
topic="$2"
{
    read # skip header row
    while read -r line; do
        echo $line | ../rpk topic produce $topic -v
    done
} < "$filename"