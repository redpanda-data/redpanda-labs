package main

import (
	"bytes"
	"compress/gzip"
	"encoding/base64"
	"encoding/json"
	"errors"
	"github.com/redpanda-data/redpanda/src/transform-sdk/go/transform"
	"io"
	"log"
	"os"
	"redactor/redactors"
)

func logError(err error) {
	log.Print(err)
}

func wrap(message string, err error) error {
	return errors.Join(errors.New(message), err)
}

func marshall(data map[string]any) ([]byte, error) {
	b, err := json.Marshal(data)
	if err != nil {
		return []byte{}, err
	}
	return b, nil
}

func unmarshall(bytes []byte) (map[string]any, error) {
	var data map[string]any
	err := json.Unmarshal(bytes, &data)
	if err != nil {
		return make(map[string]any), err
	}
	return data, nil
}

func redact(bytes []byte) ([]byte, error) {
	data, err := unmarshall(bytes)
	if err != nil {
		return []byte{}, wrap("unable to unmarshall record", err)
	}
	err = redactors.Process(data)
	if err != nil {
		return []byte{}, wrap("unable to redact record", err)
	}
	bytes, err = marshall(data)
	if err != nil {
		return []byte{}, wrap("unable to marshall record", err)
	}
	return bytes, nil
}

func decodeConfig(s string) ([]byte, error) {
	data, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		return []byte{}, wrap("unable to base64 decode config", err)
	}
	reader, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		return []byte{}, wrap("unable to decompress config", err)
	}
	uncompressed, err := io.ReadAll(reader)
	if err != nil {
		return []byte{}, wrap("unable to read config into []byte", err)
	}
	return uncompressed, nil
}

func initialise(bytes []byte) error {
	err := redactors.Configure([]byte(redactors.Builtins))
	if err != nil {
		return wrap("unable to configure built-in redactors", err)
	}
	err = redactors.Configure(bytes)
	if err != nil {
		return wrap("unable to configure custom redactors", err)
	}
	return nil
}

func main() {
	// Register your transform function.
	// This is a good place to perform other setup too.
	config, err := decodeConfig(os.Getenv("CONFIG"))
	if err != nil {
		logError(wrap("unable to decode config", err))
		return
	}
	err = initialise(config)
	if err != nil {
		logError(wrap("unable to initialise config", err))
	}
	transform.OnRecordWritten(doTransform)
}

// doTransform is where you read the record that was written, and then you can
// return new records that will be written to the output topic
func doTransform(e transform.WriteEvent) ([]transform.Record, error) {
	var result []transform.Record
	redacted, err := redact(e.Record().Value)
	if err != nil {
		return nil, wrap("unable to redact record", err)
	}
	var record = transform.Record{Headers: e.Record().Headers, Key: e.Record().Key, Value: redacted}
	result = append(result, record)
	return result, nil
}
