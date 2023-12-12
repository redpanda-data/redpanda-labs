export CONFIG=$(cat config.yaml | gzip | base64)

rpk transform deploy --env-var="CONFIG=${CONFIG}"