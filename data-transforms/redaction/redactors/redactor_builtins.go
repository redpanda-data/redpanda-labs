package redactors

var Builtins = `
redactors:
  - name: "drop"
    type: "drop"
  - name: "clear"
    type: "value"
    quote: true
    value:
      function: "replace"
      replacement: ""
  - name: "redact"
    type: "value"
    quote: true
    value:
      function: "replace"
      replacement: "REDACTED"
  - name: "redactEmailUsername"
    type: "value"
    quote: true
    value:
      function: "replaceBeforeSeparator"
      replacement: "redacted"
      separator: "@"
  - name: "truncate"
    type: "key-value"
    key:
      function: "camelPrepend"
      prefix: "truncated"
    value:
      function: "truncateFloat64"
      decimals: 1
  - name: "md5"
    type: "key-value"
    quote: true
    key:
      function: "camelPrepend"
      prefix: "hashed"
    value:
      function: "md5"
  - name: "x-digits"
    type: "value"
    quote: true
    value:
      function: "x-digits"
      i: 4
`
