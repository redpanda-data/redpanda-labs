package main

import (
	"bufio"
	"bytes"
	"io"
	"math"
	"os"
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
	// firstName is a redacted field, so is replaced by REDACTED
	redacted := redact([]byte("{\"firstName\": \"Secret\"}"))
	expected := marshall(unmarshall([]byte("{\"firstName\": \"REDACTED\"}")))

	if bytes.Compare(redacted, expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", string(expected), string(redacted))
	}
}

func TestNotRedacted(t *testing.T) {
	// name is not a redacted field, only firstName or lastName
	redacted := redact([]byte("{\"name\": \"Secret\"}"))
	expected := marshall(unmarshall([]byte("{\"name\": \"Secret\"}")))

	if bytes.Compare(redacted, expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", string(expected), string(redacted))
	}
}

func TestOwlOrder(t *testing.T) {
	redacted := redact(getBytes("test/sample.json"))
	expected := marshall(unmarshall(getBytes("test/expected.json")))

	if bytes.Compare(redacted, expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", string(expected), string(redacted))
	}
}

func TestEmailRedaction(t *testing.T) {

	original := "first.last@gmail.com"
	redacted, err := redactEmailUsername(original)
	maybeDie(err)
	expected := "redacted@gmail.com"

	if strings.Compare(redacted.(string), expected) != 0 {
		t.Errorf("\nexpected:\n%s\ngot:\n%s", expected, redacted)
	}
}

const float64EqualityThreshold = 1e-9

func almostEqual(a, b float64) bool {
	return math.Abs(a-b) <= float64EqualityThreshold
}

func TestLocationRedaction(t *testing.T) {
	original := -74.870911
	redacted, err := redactLocation(original)
	maybeDie(err)
	expected := -74.9

	if !almostEqual(redacted.(float64), expected) {
		t.Errorf("\nexpected:\n%f\ngot:\n%f", expected, redacted)
	}
}
