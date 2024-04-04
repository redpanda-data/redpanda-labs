#!/bin/bash
set -x

# Check if the correct number of arguments are passed
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <topic_name> <user_input>"
    exit 1
fi

# The first command line argument is the topic name
TOPIC_NAME="$1"

# The second command line argument is the user input (message)
USER_INPUT="$2"

# Try to process the input with jq. If it fails, treat it as a plain string.
if ! PROCESSED_JSON=$(echo "$USER_INPUT" | jq -c '.' 2>/dev/null); then
    # If input is not JSON, encode the raw input string
    PROCESSED_JSON=$(echo -n "$USER_INPUT" | base64)
else
    # If input is JSON, encode the jq-processed JSON string
    PROCESSED_JSON=$(echo -n "$PROCESSED_JSON" | base64)
fi

echo "Prepared Message: $PROCESSED_JSON"

expect <<EOF
# Launch your command
spawn rpk topic produce $TOPIC_NAME

# Send the prepared JSON message as input
send -- [exec echo "$PROCESSED_JSON" | base64 --decode]\r

# Wait a bit to ensure 'rpk' processes the message
# Adjust the sleep time based on how long 'rpk' typically takes
sleep 5

# Send SIGINT (CTRL+C)
send "\003"

expect eof
EOF

echo "Script completed."
