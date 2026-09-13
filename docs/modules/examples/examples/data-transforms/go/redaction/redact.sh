SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

TEST=`go run cmd/redact.go "$@" >/dev/null 2>/dev/null`

if [ $? -eq 0 ]
then
  # Optional pretty printing via jq
  if command -v jq &> /dev/null
  then
      go run cmd/redact.go "$@" | jq
      exit
  fi
else
  go run cmd/redact.go "$@"
fi