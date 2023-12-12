package redactors

import (
	"math"
	"strings"
	"testing"
)

func TestConfig(t *testing.T) {
	conf := "redactors:\n  - name: \"redact\"\n    config:\n      function: \"replace\"\n      replacement: \"REDACTED\"\n  - name: \"redactEmailUsername\"\n    config:\n      function: \"replaceBeforeSeparator\"\n      replacement: \"redacted\"\n      separator: \"@\"\n  - name: \"redactLocation\"\n    config:\n      function: \"truncateFloat64\"\n      decimals: 1"
	config, err := GetConfig([]byte(conf))
	if err != nil {
		t.Error(err)
	}
	if len(config.Redactors) != 3 {
		t.Error("expected 3 redactors to be defined")
	}
}

func TestBuilder(t *testing.T) {
	conf := "redactors:\n  - name: \"redact\"\n    config:\n      function: \"replace\"\n      replacement: \"REDACTED\"\n  - name: \"redactEmailUsername\"\n    config:\n      function: \"replaceBeforeSeparator\"\n      replacement: \"redacted\"\n      separator: \"@\"\n  - name: \"redactLocation\"\n    config:\n      function: \"truncateFloat64\"\n      decimals: 1"
	config, err := GetConfig([]byte(conf))
	if err != nil {
		t.Error(err)
	}
	redactors, err := GetRedactors(*config)
	if len(redactors) != 3 {
		t.Error("expected 3 redactors to be defined")
	}
}

func TestReplace(t *testing.T) {
	expected := "REDACTED"
	var config = map[string]any{"function": "replace", "replacement": expected}
	f, err := buildFunction(config)
	if err != nil {
		t.Error(err)
	}
	redacted, _ := f("foo") // Any input is discarded with the replacer
	if strings.Compare(redacted.(string), expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}

func TestReplaceBeforeSeparator(t *testing.T) {
	expected := "redacted@email.com"
	var config = map[string]any{"function": "replaceBeforeSeparator", "replacement": "redacted", "separator": "@"}
	f, err := buildFunction(config)
	if err != nil {
		t.Error(err)
	}
	redacted, _ := f("anything@email.com") // Any input is discarded with the replacer
	if strings.Compare(redacted.(string), expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}

func TestTruncateFloat64(t *testing.T) {
	expected := 3.1
	var config = map[string]any{"function": "truncateFloat64", "decimals": 1}
	f, err := buildFunction(config)
	if err != nil {
		t.Error(err)
	}
	redacted, _ := f(3.141593) // Any input is discarded with the replacer
	if !almostEqual(redacted.(float64), expected) {
		t.Errorf("\nexpected:\n%f\ngot:\n%f", expected, redacted)
	}
}

const float64EqualityThreshold = 1e-9

func almostEqual(a, b float64) bool {
	return math.Abs(a-b) <= float64EqualityThreshold
}
