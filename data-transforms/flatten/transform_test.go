package main

import (
	"bytes"
	"strings"
	"testing"
)

var sampleJson = `{
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
`

var sampleJsonWithRootElements = `{
  "some_content": "test",
  "id:": 1234,
  "content": {
    "id": 123,
    "name": {
      "first": "Dave",
      "middle": null,
      "last": "Voutila"
    }
  }
}
`

var newFlattenedJson = `{
  "some_content": "test",
  "id:": 1234,
  "content.id": 123,
  "content.name.first": "Dave",
  "content.name.middle": null,
  "content.name.last": "Voutila"
}
`

var flattenedJson = `{
  "content.id": 123,
  "content.name.first": "Dave",
  "content.name.middle": null,
  "content.name.last": "Voutila",
  "content.data": [1, "fish", 2, "fish"]
}
`

func TestJSONStream(t *testing.T) {
	bufIn := bytes.NewBufferString(sampleJson)
	bufOut := bytes.NewBuffer([]byte{})
	err := Flatten(bufIn, bufOut, ".")
	if err != nil {
		t.Fatal(err)
	}

	result := bufOut.String()

	if strings.Compare(flattenedJson, result) != 0 {
		t.Errorf("expected:\n%sgot:\n%s", flattenedJson, result)
	}
}

func TestJsonStreamWithRootElements(t *testing.T) {
  bufIn := bytes.NewBufferString(sampleJsonWithRootElements)
  bufOut := bytes.NewBuffer([]byte{})

  err := Flatten(bufIn, bufOut, ".")
  if err != nil {
    t.Fatal(err)
  }

  result := bufOut.String()

  if strings.Compare(newFlattenedJson, result) != 0 {
    t.Errorf("expected:\n%sgot:\n%s", newFlattenedJson, result)
  }
}
