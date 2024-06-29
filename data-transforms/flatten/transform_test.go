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

var sampleComplexJson = `{
  "id": 1234,
  "content": {
    "id": 123,
    "name": {
      "first": "Dave",
      "middle": null
    },
    "addresses": [
      {
        "street":"someStreet",
        "appartments":[]
      },
      {
        "street":"someOtherStreet",
        "appartments":[ 1, 2, 3, 4 ]
      }
    ]
  },
  "data": [1, "fish", 2, "fish"],
  "more_data": {
    "id": 123,
    "empty": {},
    "name": {
      "first": "Bob",
      "middle": "Jr"
    }
  },
  "content": "test",
  "empty_again": {}
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

var flattenedComplexJson = `{
  "id": 1234,
  "content.id": 123,
  "content.name.first": "Dave",
  "content.name.middle": null,
  "content.addresses.0.street": "someStreet",
  "content.addresses.0.appartments": [],
  "content.addresses.1.street": "someOtherStreet",
  "content.addresses.1.appartments": [1, 2, 3, 4],
  "data": [1, "fish", 2, "fish"],
  "more_data.id": 123,
  "more_data.empty": {},
  "more_data.name.first": "Bob",
  "more_data.name.middle": "Jr",
  "content": "test",
  "empty_again": {}
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


func TestComplexJsonStream(t *testing.T) {
  bufIn := bytes.NewBufferString(sampleComplexJson)
  bufOut := bytes.NewBuffer([]byte{})

  err := Flatten(bufIn, bufOut, ".")
  if err != nil {
    t.Fatal(err)
  }

  result := bufOut.String()

  if strings.Compare(flattenedComplexJson, result) != 0 {
    t.Errorf("expected:\n%sgot:\n%s", flattenedComplexJson, result)
  }
}
