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
	redacted, _ := f("foo")
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
	redacted, _ := f("anything@email.com")
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
	redacted, _ := f(3.141593)
	if !almostEqual(redacted.(float64), expected) {
		t.Errorf("\nexpected:\n%f\ngot:\n%f", expected, redacted)
	}
}

const float64EqualityThreshold = 1e-9

func almostEqual(a, b float64) bool {
	return math.Abs(a-b) <= float64EqualityThreshold
}

func TestMD5(t *testing.T) {
	expected := "acbd18db4cc2f85cedef654fccc4a4d8"
	var config = map[string]any{"function": "md5"}
	f, err := buildFunction(config)
	if err != nil {
		t.Error(err)
		return
	}
	redacted, _ := f("foo")
	if strings.Compare(redacted.(string), expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}

func TestSHA1(t *testing.T) {
	expected := "0beec7b5ea3f0fdbc95d0dd47f3c5bc275da8a33"
	var config = map[string]any{"function": "sha1"}
	f, err := buildFunction(config)
	if err != nil {
		t.Error(err)
		return
	}
	redacted, _ := f("foo")
	if strings.Compare(redacted.(string), expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}
