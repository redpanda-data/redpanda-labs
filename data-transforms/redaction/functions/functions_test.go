package functions

import (
	"bytes"
	"github.com/pmw-rp/jsonparser"
	"math"
	"reflect"
	"testing"
)

const float64EqualityThreshold = 1e-9

func almostEqual(a, b float64) bool {
	return math.Abs(a-b) <= float64EqualityThreshold
}

func almostEqualByteSlice(a, b []byte) bool {
	af, err := jsonparser.ParseFloat(a)
	if err != nil {
		panic(0)
	}
	bf, err := jsonparser.ParseFloat(b)
	if err != nil {
		panic(0)
	}
	return math.Abs(af-bf) <= float64EqualityThreshold
}

func TestValidateConfig(t *testing.T) {
	config := map[string]any{"a": "foo", "b": 1}
	err := validateConfig(config, map[string]reflect.Kind{"a": reflect.String, "b": reflect.Int})
	if err != nil {
		t.Error(err)
	}
}

func TestValidateConfigMissingEntry(t *testing.T) {
	config := map[string]any{"a": "foo", "b": 1}
	err := validateConfig(config, map[string]reflect.Kind{"c": reflect.String})
	if err != nil {
		return
	}
	t.Fail()
}

func TestValidateConfigWrongType(t *testing.T) {
	config := map[string]any{"a": "foo", "b": 1}
	err := validateConfig(config, map[string]reflect.Kind{"c": reflect.String})
	if err != nil {
		return
	}
	t.Fail()
}

func TestValidateValue(t *testing.T) {
	value := "foo"
	err := validateValue(value, reflect.String)
	if err != nil {
		t.Error(err)
	}
}

func TestValidateValueWrongType(t *testing.T) {
	value := "foo"
	err := validateValue(value, reflect.Int)
	if err != nil {
		return
	}
	t.Fail()
}

func TestReplace(t *testing.T) {
	expected := []byte("bar")
	redacted, err := replace([]byte("foo"), expected)
	if err != nil {
		t.Error(err)
		return
	}
	if bytes.Compare(redacted, expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}

func TestReplaceViaBuildFunction(t *testing.T) {
	expected := "bar"
	fn, err := BuildFunction(map[string]any{"function": "replace", "replacement": expected})
	if err != nil {
		t.Error(err)
		return
	}
	redacted, err := fn([]byte("foo"))
	if err != nil {
		t.Error(err)
		return
	}
	if bytes.Compare(redacted, []byte(expected)) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}

func TestReplaceFunctionMissingParameter(t *testing.T) {
	_, err := BuildFunction(map[string]any{"function": "replace", "replacement": true})
	if err != nil {
		return
	} else {
		t.Fail()
	}
}

func TestReplaceFunctionParameterWrongType(t *testing.T) {
	_, err := BuildFunction(map[string]any{"function": "replace"})
	if err != nil {
		return
	} else {
		t.Fail()
	}
}

func TestReplaceBeforeSeparator(t *testing.T) {
	expected := "redacted@email.com"
	var config = map[string]any{"function": "replaceBeforeSeparator", "replacement": "redacted", "separator": "@"}
	f, err := BuildFunction(config)
	if err != nil {
		t.Error(err)
	}
	redacted, _ := f([]byte("anything@email.com")) // Any input is discarded with the replacer
	if bytes.Compare(redacted, []byte(expected)) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}

func TestTruncateFloat64(t *testing.T) {
	expected := []byte("3.1")
	var config = map[string]any{"function": "truncateFloat64", "decimals": 1}
	f, err := BuildFunction(config)
	if err != nil {
		t.Error(err)
	}
	redacted, _ := f([]byte("3.141593")) // Any input is discarded with the replacer
	if !almostEqualByteSlice(redacted, expected) {
		//t.Errorf("\nexpected:\n%f\ngot:\n%f", expected, redacted)
		t.Fail()
	}
}

func TestMD5(t *testing.T) {
	expected := "acbd18db4cc2f85cedef654fccc4a4d8"
	var config = map[string]any{"function": "md5"}
	f, err := BuildFunction(config)
	if err != nil {
		t.Error(err)
		return
	}
	redacted, _ := f([]byte("foo"))
	if bytes.Compare(redacted, []byte(expected)) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}

func TestSHA1(t *testing.T) {
	expected := "0beec7b5ea3f0fdbc95d0dd47f3c5bc275da8a33"
	var config = map[string]any{"function": "sha1"}
	f, err := BuildFunction(config)
	if err != nil {
		t.Error(err)
		return
	}
	redacted, _ := f([]byte("foo"))
	if bytes.Compare(redacted, []byte(expected)) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}

func TestPrepend(t *testing.T) {
	expected := "foobar"
	var config = map[string]any{"function": "prepend", "prefix": "foo"}
	f, err := BuildFunction(config)
	if err != nil {
		t.Error(err)
		return
	}
	redacted, _ := f([]byte("bar"))
	if bytes.Compare(redacted, []byte(expected)) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}

func TestCamelPrepend(t *testing.T) {
	expected := []byte("fooBar")
	redacted, err := camelPrepend([]byte("bar"), []byte("foo"))
	if err != nil {
		t.Error()
	}
	if bytes.Compare(redacted, expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}

func TestAppendString(t *testing.T) {
	expected := "foobar"
	var config = map[string]any{"function": "append", "suffix": "bar"}
	f, err := BuildFunction(config)
	if err != nil {
		t.Error(err)
		return
	}
	redacted, _ := f([]byte("foo"))
	if bytes.Compare(redacted, []byte(expected)) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}

func TestXDigits(t *testing.T) {
	input := "123-4567-8900"
	expected := "XXX-XXXX-8900"
	var config = map[string]any{"function": "x-digits", "i": 4}
	f, err := BuildFunction(config)
	if err != nil {
		t.Error(err)
		return
	}
	redacted, _ := f([]byte(input))
	if bytes.Compare(redacted, []byte(expected)) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}
