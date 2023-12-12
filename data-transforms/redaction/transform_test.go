package main

import (
	"bufio"
	"bytes"
	"io"
	"os"
	"redactor/redactors"
	"strings"
	"testing"
)

func getBytes(filename string) []byte {
	file, err := os.Open(filename)
	maybeDie(err)

	// Get the file size
	stat, err := file.Stat()
	maybeDie(err)

	// Read the file into a byte slice
	bs := make([]byte, stat.Size())
	_, err = bufio.NewReader(file).Read(bs)
	if err != nil && err != io.EOF {
		maybeDie(err)
	}

	return bs
}

func TestSimple(t *testing.T) {
	initialise(getBytes("config.yaml"))
	// firstName is a redacted field, so is replaced by REDACTED
	redacted := redact([]byte("{\"firstName\": \"Secret\"}"))
	expected := marshall(unmarshall([]byte("{\"firstName\": \"REDACTED\"}")))

	if bytes.Compare(redacted, expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", string(expected), string(redacted))
	}
}

func TestNotRedacted(t *testing.T) {
	initialise(getBytes("config.yaml"))
	// name is not a redacted field, only firstName or lastName
	redacted := redact([]byte("{\"name\": \"Secret\"}"))
	expected := marshall(unmarshall([]byte("{\"name\": \"Secret\"}")))

	if bytes.Compare(redacted, expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", string(expected), string(redacted))
	}
}

func TestOwlOrder(t *testing.T) {
	initialise(getBytes("config.yaml"))
	redacted := redact(getBytes("test/sample.json"))
	expected := marshall(unmarshall(getBytes("test/expected.json")))

	if bytes.Compare(redacted, expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", string(expected), string(redacted))
	}
}

func TestEmailRedaction(t *testing.T) {
	initialise(getBytes("config.yaml"))
	original := marshall(unmarshall([]byte("{\"email\":\"first.last@email.com\"}")))
	redacted := redact(original)
	expected := "{\"email\":\"redacted@email.com\"}"

	if strings.Compare(string(redacted), expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}

func TestLocationRedaction(t *testing.T) {
	initialise(getBytes("config.yaml"))
	original := marshall(unmarshall([]byte("{\"latitude\":-74.870911}")))
	redacted := redact(original)
	expected := "{\"latitude\":-74.9}"

	if strings.Compare(string(redacted), expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}

func TestDecodeConfig(t *testing.T) {
	data := "H4sIAB59eGUAA41Qu27DMAzc/RWE9g4Big6e2jTuFGTo4wMYiXYESKJB0f9f2YmBxHHQbtQddXc8IYdWWXJdATxBwkg1GJlQUyAAy6n1XT3NAO2QrHpO01If0JK5MJdnpKSF/Gx2b+/fzc7cyzYRffjJJCP6P48ttSz0RT0KlrDrlmd1cjOb5/XCva7k2LPF0eaPCCplRqWPwKgvz7O6I+sjhlzDpqrOgmV/qtG0XrIexutuujQBV+GOkiNZgCceMh2GeLxjsgqRLsD+xGmpS2PR5nHvJY96HdzVv+tOTODUPeJ/AdFABag4AgAA"
	bytes := decodeConfig(data)
	config, err := redactors.GetConfig(bytes)
	if err != nil {
		t.Error()
	}
	if len(config.Redactions) != 9 {
		t.Error()
	}
}
