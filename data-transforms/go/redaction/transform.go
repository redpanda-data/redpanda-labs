package main

import (
	"bytes"
	"compress/gzip"
	"encoding/base64"
	"github.com/redpanda-data/redpanda/src/transform-sdk/go/transform"
	"io"
	"log"
	"os"
	"redactor/redaction"
)

func logError(err error) {
	log.Print(err)
}

func decodeConfig(s string) ([]byte, error) {
	data, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		return []byte{}, redaction.Wrap("unable to base64 decode config", err)
	}
	reader, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		return []byte{}, redaction.Wrap("unable to decompress config", err)
	}
	uncompressed, err := io.ReadAll(reader)
	if err != nil {
		return []byte{}, redaction.Wrap("unable to read config into []byte", err)
	}
	return uncompressed, nil
}

func main() {
	// Register your transforms function.
	// This is a good place to perform other setup too.
	config, err := decodeConfig(os.Getenv("CONFIG"))
	if err != nil {
		logError(redaction.Wrap("unable to decode config", err))
		return
	}
	err = redaction.Initialise(config)
	if err != nil {
		logError(redaction.Wrap("unable to initialise config", err))
	}
	transform.OnRecordWritten(doTransform)
}

// doTransform is where you read the record that was written, and then you can
// return new records that will be written to the output topic
func doTransform(e transform.WriteEvent) ([]transform.Record, error) {
	var result []transform.Record
	redacted, err := redaction.Redact(e.Record().Value)
	if err != nil {
		return nil, redaction.Wrap("unable to redact record", err)
	}
	var record = transform.Record{Headers: e.Record().Headers, Key: e.Record().Key, Value: redacted}
	result = append(result, record)
	return result, nil
}
