package redactors

var Builtins = `
redactors:
  - name: "drop"
    type: "drop"
  - name: "clear"
    type: "value"
    value:
      function: "replace"
      replacement: ""
  - name: "redact"
    type: "value"
    value:
      function: "replace"
      replacement: "REDACTED"
  - name: "redactEmailUsername"
    type: "value"
    value:
      function: "replaceBeforeSeparator"
      replacement: "redacted"
      separator: "@"
  - name: "redactLocation"
    type: "both"
    key:
      function: "camelPrepend"
      prefix: "truncated"
    value:
      function: "truncateFloat64"
      decimals: 1
  - name: "md5"
    type: "both"
    key:
      function: "camelPrepend"
      prefix: "hashed"
    value:
      function: "md5"
`
