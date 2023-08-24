# Redpanda Wasm Data Transform - Regex Filter

This contains an example of using a regular expression to filter a topic into another.

Regular expression are implemented using Go's regexp library, which uses the same syntax as RE2.
See the RE2 wiki for allowed syntax: https://github.com/google/re2/wiki/Syntax

Environment variables:
- `PATTERN`: The regular expression that will match against records (required)
- `MATCH_VALUE`: By default, the regex matches keys, but if set to true, the regex will match values

To deploy this to a cluster you'll need to run the following in this directory:
```
rpk transform build
rpk transform deploy --env-var=PATTERN=myregex --input-topic=src --output-topic=sink
```
