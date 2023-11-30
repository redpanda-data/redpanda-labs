# Redpanda Wasm Data Transform - Flatten

This project provides a JSON flattener, taking input JSON such as:

```json
{
  "content": {
    "id": 123,
    "name": {
      "first": "Dave",
      "middle": null,
      "last": "Voutila"
    },
    "data": [1, "fish", 2, "fish"]
  }
}
```

Turning it into:

```json
{
  "content.id": 123,
  "content.name.first": "Dave",
  "content.name.middle": null,
  "content.name.last": "Voutila",
  "content.data": [1, "fish", 2, "fish"]
}
```

> Note: currently, thanks to how JSON works, floating point values
> like `1.0` that can be converted to an integer will end up dropping
> the decimal point. (e.g. `1.0 => 1`)

## Limitations

- Arrays of Objects are currently untested.
- Providing a series of Objects as input, not an an Array, may result
  in a series of flattened Objects as output.

## Building & Installing

To get started you first need to have at least go 1.20 installed.

Once you're ready to test out your transform live you need to:

1. Make sure you have Redpanda running.
2. Run `rpk transform build -- -scheduler=asyncify`.
3. Create your topics via `rpk topic create`.
4. Run `rpk transform deploy`.

## Configuring

The delimitter used defaults to `.` but may be changed by setting the
`RP_FLATTEN_DELIM` environment variable. This is done during
deployment:

```
$ rpk transform deploy --env-var "RP_FLATTEN_DELIM=-"
```
