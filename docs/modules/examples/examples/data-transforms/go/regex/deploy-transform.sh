#!/bin/bash

rpk transform deploy --var=PATTERN="\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\\b" --var=MATCH_VALUE=true --input-topic=src --output-topic=sink