SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if ! [ -f $1 ]; then
  echo "Config file doesn't exist."
  exit 1
fi

export CONFIG=$(gzip < "${1}" | base64 -w 0)

cat << EOF > "${SCRIPT_DIR}"/transform.yaml
name: $3-transform
input-topic: "$2"
output-topic: "$3"
language: tinygo-no-goroutines
EOF

rpk transform build
rpk transform deploy --var="CONFIG=${CONFIG}"

rm "${SCRIPT_DIR}"/transform.yaml