# Redaction Transform (Redpanda Golang WASM Transform)

This transform is designed to redact PII data in JSON messages.

# Overview

The transform works by iterating over a list of redactions to perform. Each redaction is defined with a JSON path and a
function to apply to that path (known as a redactor).

### Redactors

A redactor is a named function that can perform the following actions:

- Drop the field entirely
- Change the value
- Change the key, equivalent to dropping the field and replacing it

There are a number of built-in redactors to use, however the redaction transform can be extended (see below).

### Built-in Redactors

The following [built-in](./redactors/redactor_builtins.go) redactors are available:

- `drop`: drop the field entirely
- `clear`: set the value string to `""`
- `redact`: set the value string to `"REDACTED"`
- `redactEmailUsername`: set the username portion of an email address in the value string to `redacted`, leaving the domain intact
- `truncateFloat`: set the value to a truncated float with 1 decimal place, while setting the renaming the key to `truncatedKey`
- `md5`: set the value to a hashed version, while renaming the key to `hashedKey`

# Usage

### Specify the redactions to perform

Customise the config.yaml file in order to specify what paths should be modified (and with what redactors):

```yaml
redactions:
 - "path": "customer"
   "type": "drop"
 - "path": "deliveryAddress.firstName"
   "type": "drop"
 - "path": "deliveryAddress.lastName"
   "type": "drop"
 - "path": "deliveryAddress.houseNumber"
   "type": "redact"
```

### Build and Deploy

The config.yaml file is gzipped and encoded as base64, then injected into the transform using the `--var` parameter -
therefore it is easier to use the supplied deploy script `deploy-redaction` in order to deploy the transform.

```shell
./deploy-redaction
```

# Custom Redaction

If the built-in redactors are insufficient, they can be extended. There are two ways to extend the functionality: 1) creating a new redactor and 2) creating new functions.

## Creating a New Redactor

You create a new redactor defining it in the configuration file - see the [built-in](./redactors/redactor_builtins.go) redactors
for examples of how to do this.

### Example: Value Redactor

A value redactor is one that changes only the value. Consider the following built-in example:

```yaml
  - name: "redact"
    type: "value"
    value:
      function: "replace"
      replacement: "REDACTED"
 ```

Here, the redactor (called `redact`) has a type of `value`, indicating that it only changes the value. The value function is specified
as `replace`, with a replacement of `redacted`.

### Example: Key-Value Redactor

A key-value redactor is one that changes both the key and the value. Consider the following built-in example:

```yaml
  - name: "md5"
    type: "key-value"
    quote: true
    key:
      function: "camelPrepend"
      prefix: "hashed"
    value:
      function: "md5"
 ```

Here, the `md5` redactor has a type of `key-value`, indicating it changes both the key and value. For the key, it uses the `camelPrepend`
function, with a prefix of `hashed`. So, when applied to a field called `name`, we get a field called `hashedName`. The value
uses a function of `md5`. Finally, it includes the parameter `quote`, set to true, which indicates that the output of the function
is a string and should be wrapped in double quotes.

## Built-in Functions

The following [built-in functions](./functions/functions.go) can be used when creating custom redactors:

- `replace`: replaces a string value (requires a `replacement`)
- `replaceBeforeSeparator`: replaces a the initial part of a string (requires a `replacement` and `separator`)
- `truncateFloat64`: reduces the precision of a floating point number (requires the number of `decimals`)
- `md5`: returns the md5 hash of a string
- `sha1`: returns the sha1 hash of a string
- `prepend`: prepends extra text to a string (requires a `prefix`)
- `camelPrepend`: prepends extra text to a string and uppercases the first letter of the original (requires a `prefix`)
- `append`: appends extra text to a string (requires a `suffix`)

# Custom Redaction Functions

In addition to the [built-in](./functions/functions.go) functions described above, it is possible to add additional functions.
This is handled by adding additional Go code within [`functions.go`](./functions/functions.go) to support your requirement.

Be sure to also add your function to the `BuildFunction` function, in order that the framework understands which Go function should
be applied.

# Custom Redactor Types

As noted above, there are [three](./redactors/redactors.go) built-in types of redactor:

- Drop the field entirely (`drop`, implemented with `DropRedactor`)
- Change the value (`value`, implemented with `ValueRedactor`)
- Replace both the key and value, thereby dropping the field and replacing it (`key-value``KeyValueRedactor`)

 While it is unlikely to need to create a new redactor type, this could be achieved by amending the `buildRedactor` function
 within [`redactors.go`](./redactors/redactors.go).