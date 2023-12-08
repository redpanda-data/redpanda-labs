# PII Redaction Transform (Redpanda Golang WASM Transform)

This transform is designed to redact PII data in JSON messages by matching on field names and using a field-dependent
redaction function.

## Usage

Customise the transform.go file in order to implement your desired redaction functionality. The example includes the
following redaction functions:

### Replace entire value with "REDACTED"

```go
func fullyRedactString(s any) (any, error) {
	return "REDACTED", nil
}
```
### Replace username portion of an email address

```go
func redactEmailUsername(s any) (any, error) {
    original, ok := s.(string)
    if ok {
        split := strings.Split(original, "@")
    return "redacted@" + split[1], nil
    } else {
		return "", errors.New("can't redact an email address, input wasn't a string")
    }
}
```

### Replace latitude / longitude with less accurate value

```go
func redactLocation(l any) (any, error) {
    original, ok := l.(float64)
    if ok {
        return strconv.ParseFloat(fmt.Sprintf("%.1f", original), 64)
    } else {
        return "", errors.New("can't redact the location, input wasn't a float64")
    }
}
```

## Customise the redaction selection

This table specifies what redaction function is applied to what field, based on the matching field name:

```go
var redactedFields = map[string]func(any) (any, error){
	"firstName":   fullyRedactString,
	"lastName":    fullyRedactString,
	"email":       redactEmailUsername,
	"gender":      fullyRedactString,
	"street":      fullyRedactString,
	"houseNumber": fullyRedactString,
	"phone":       fullyRedactString,
	"latitude":    redactLocation,
	"longitude":   redactLocation,
}
```

# Build and Deploy

```shell
rpk transform build
rpk transform deploy
```