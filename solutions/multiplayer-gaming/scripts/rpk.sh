#!/bin/sh
# Mounted over /usr/local/bin/rpk in the rpk helper container.
#
# docker-compose.yml passes the connection variables from .env to rpk as
# RPK_* names. On the local path the SASL ones are empty, and rpk treats an
# empty RPK_SASL_MECHANISM as a mechanism to negotiate, which fails with
# ILLEGAL_SASL_STATE. Empty means "not configured", so drop them first.
for v in RPK_SASL_MECHANISM RPK_USER RPK_PASS; do
  eval "val=\${$v}"
  [ -z "$val" ] && unset "$v"
done
exec /usr/bin/rpk "$@"
