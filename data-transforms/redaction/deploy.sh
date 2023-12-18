export CONFIG=$(cat config.yaml | gzip | base64)

rpk transform deploy --var="CONFIG=${CONFIG}"