package main

import (
	"redactor/redactors"
	"reflect"
	"testing"
)

func TestEverything(t *testing.T) {
	redactors.Clear()
	config := "redactions:\n name: md5\n ssn: drop\n gender: drop\n latitude: redactLocation"
	err := initialise([]byte(config))
	if err != nil {
		t.Error(err)
		return
	}
	data := map[string]any{"name": "paul", "ssn": 12345, "gender": "male", "latitude": 55.123456, "other": "safe", "customer": map[string]any{"id": "123", "name": "foo"}}
	expected := map[string]any{"hashedName": "6c63212ab48e8401eaf6b59b95d816a9", "truncatedLatitude": 55.1, "other": "safe", "customer": map[string]any{"id": "123", "hashedName": "acbd18db4cc2f85cedef654fccc4a4d8"}}
	err = redactors.Process(data)
	if err != nil {
		t.Error(err)
		return
	}

	eq := reflect.DeepEqual(data, expected)
	if !eq {
		t.Fail()
	}
}
