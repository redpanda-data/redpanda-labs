# Redaction Transform (Redpanda Golang WASM Transform)

This transform is designed to redact PII data in JSON messages by matching on field names and using a field-dependent
redaction function.

## Usage

Customise the config.yaml file in order to define what redaction functions you want and what fields they should apply to:

```yaml
redactors:
  - name: "redact"
    config:
      function: "replace"
      replacement: "REDACTED"
  - name: "redactEmailUsername"
    config:
      function: "replaceBeforeSeparator"
      replacement: "redacted"
      separator: "@"
  - name: "redactLocation"
    config:
      function: "truncateFloat64"
      decimals: 1

redactions:
  "firstName": "redact"
  "lastName": "redact"
  "gender": "redact"
  "houseNumber": "redact"
  "street": "redact"
  "phone": "redact"
  "email": "redactEmailUsername"
  "latitude": "redactLocation"
  "longitude": "redactLocation"
```

Notice that we define redaction functions once. Every field that should be redacted using that function references it by name.

## Redaction Functions

There are three built-in redaction functions, but these can be extended by adding additional Go code to support your requirement.

(Add the function in `redactors.go` and ensure it is included within the builder function)

### Replace entire value ("replace")

```go
func replace(input string, replacement string) (string, error) {
    return replacement, nil
}
```
### Replace a portion before a separator

```go
func replaceBeforeSeparator(input string, replacement string, separator string) (string, error) {
    if !strings.Contains(input, separator) {
        return "", errors.New(fmt.Sprintf("input string \"%s\" doesn't contain separator \"%s\"", input, separator))
    }
    split := strings.Split(input, separator)
    if len(split) != 2 {
        return "", errors.New(fmt.Sprintf("input string \"%s\" contains multiple separators \"%s\"", input, separator))
    }
    return replacement + separator + split[1], nil
}
```

### Truncate a float with a less accurate value

```go
func truncateFloat64(input float64, decimals int) (float64, error) {
    format := "%." + strconv.Itoa(decimals) + "f"
    s := fmt.Sprintf(format, input)
    return strconv.ParseFloat(s, 64)
}
```

# Build and Deploy

The config.yaml file is gzipped and encoded as base64, then injected into the transform using the `--env-var` parameter - 
therefore it is easier to use the supplied deploy script `deploy.sh` in order to deploy the transform.

```shell
rpk transform build
./deploy.sh
```