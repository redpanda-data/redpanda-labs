package redactors

import (
	"strings"
	"testing"
)

// Test DropRedactor

type DropRedactorAPIMock struct {
	t *testing.T
}

func (api *DropRedactorAPIMock) getKey() string {
	api.t.Fail()
	return ""
}

func (api *DropRedactorAPIMock) getValue() any {
	api.t.Fail()
	return ""
}

func (api *DropRedactorAPIMock) add(key string, value any) {
	api.t.Fail()
}

func (api *DropRedactorAPIMock) drop() {

}

func (api *DropRedactorAPIMock) setValue(value any) {
	api.t.Fail()
}

func TestDropRedactor(t *testing.T) {
	conf := RedactorConf{Name: "drop", Type: "drop"}
	redactor, err := buildRedactor(conf)
	if err != nil {
		t.Error(err)
		return
	}
	api := DropRedactorAPIMock{t: t}
	err = redactor.redact(&api)
	if err != nil {
		t.Error(err)
	}
}

//////// Test ValueRedactor

type ValueRedactorAPIMock struct {
	t       *testing.T
	value   any
	opCount int
}

func (api *ValueRedactorAPIMock) getKey() string {
	api.t.Fail()
	return ""
}

func (api *ValueRedactorAPIMock) getValue() any {
	if api.opCount == 0 {
		api.opCount = api.opCount + 1
		return api.value
	} else {
		api.t.Fail()
		return nil
	}
}

func (api *ValueRedactorAPIMock) add(key string, value any) {
	api.t.Fail()
}

func (api *ValueRedactorAPIMock) drop() {
	api.t.Fail()
}

func (api *ValueRedactorAPIMock) setValue(value any) {
	if api.opCount == 1 {
		api.opCount = api.opCount + 1
		api.value = value
	} else {
		api.t.Fail()
	}
}

func TestValueRedactor(t *testing.T) {
	conf := RedactorConf{Name: "clear", Type: "value", Value: map[string]any{"function": "replace", "replacement": ""}}
	redactor, err := buildRedactor(conf)
	if err != nil {
		t.Error(err)
		return
	}
	api := ValueRedactorAPIMock{t: t, value: "foo", opCount: 0}
	err = redactor.redact(&api)
	if err != nil {
		t.Error(err)
	}
	expected := ""
	redacted := api.value.(string)
	if strings.Compare(redacted, expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}

//////// Test KeyValueRedactor

type KeyValueRedactorAPIMock struct {
	t       *testing.T
	key     string
	value   any
	opCount int
}

func (api *KeyValueRedactorAPIMock) getKey() string {
	if api.opCount == 0 {
		api.opCount = api.opCount + 1
		return api.key
	} else {
		api.t.Fail()
		return ""
	}
}

func (api *KeyValueRedactorAPIMock) getValue() any {
	if api.opCount == 1 {
		api.opCount = api.opCount + 1
		return api.value
	} else {
		api.t.Fail()
		return nil
	}
}

func (api *KeyValueRedactorAPIMock) add(key string, value any) {
	if api.opCount == 3 {
		api.opCount = api.opCount + 1
		api.key = key
		api.value = value
	} else {
		api.t.Fail()
	}
}

func (api *KeyValueRedactorAPIMock) drop() {
	if api.opCount == 2 {
		api.opCount = api.opCount + 1
	} else {
		api.t.Fail()
	}
}

func (api *KeyValueRedactorAPIMock) setValue(value any) {
	api.t.Fail()
}

func TestKeyValueRedactor(t *testing.T) {
	conf := RedactorConf{Name: "md5", Type: "both", Key: map[string]any{"function": "camelPrepend", "prefix": "hashed"}, Value: map[string]any{"function": "md5"}}
	redactor, err := buildRedactor(conf)
	if err != nil {
		t.Error(err)
		return
	}
	api := KeyValueRedactorAPIMock{t: t, key: "foo", value: "bar", opCount: 0}
	err = redactor.redact(&api)
	if err != nil {
		t.Error(err)
	}

	expectedKey := "hashedFoo"
	redactedKey := api.key
	if strings.Compare(redactedKey, expectedKey) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expectedKey, redactedKey)
	}

	expectedValue := "37b51d194a7513e45b56f6524f2d51f2"
	redactedValue := api.value.(string)
	if strings.Compare(redactedValue, expectedValue) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expectedValue, redactedValue)
	}
}
