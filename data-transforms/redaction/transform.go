package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"github.com/redpanda-data/redpanda/src/transform-sdk/go/transform"
	"log"
	"reflect"
	"strconv"
	"strings"
)

func maybeDie(err error) {
	if err != nil {
		log.Fatal(err)
	}
}

func unmarshall(bytes []byte) map[string]any {
	var objmap map[string]any
	if err := json.Unmarshal(bytes, &objmap); err != nil {
		log.Fatal(err)
	}
	return objmap
}

var redactedFields = map[string]func(any) (any, error){
	"firstName":   fullyRedactString,
	"lastName":    fullyRedactString,
	"email":       redactEmailUsername,
	"gender":      fullyRedactString,
	"street":      fullyRedactString,
	"houseNumber": fullyRedactString,
	"phone":       fullyRedactString,
	"latitude":    redactLocation,
	"longitude":   redactLocation,
}

var basicTypes = map[string]bool{
	"string":     true,
	"bool":       true,
	"float32":    true,
	"float64":    true,
	"rune":       true,
	"byte":       true,
	"complex64":  true,
	"complex128": true,
	"int":        true,
	"int8":       true,
	"int16":      true,
	"int32":      true,
	"int64":      true,
	"uint":       true,
	"uint8":      true,
	"uint16":     true,
	"uint32":     true,
	"uint64":     true,
	"uintptr":    true,
}

func fullyRedactString(s any) (any, error) {
	return "REDACTED", nil
}

func redactEmailUsername(s any) (any, error) {
	original, ok := s.(string)
	if ok {
		split := strings.Split(original, "@")
		return "redacted@" + split[1], nil
	} else {
		return "", errors.New("can't redact an email address, input wasn't a string")
	}
}

func redactLocation(l any) (any, error) {
	original, ok := l.(float64)
	if ok {
		return strconv.ParseFloat(fmt.Sprintf("%.1f", original), 64)
	} else {
		return "", errors.New("can't redact the location, input wasn't a float64")
	}
}

func isABasicType(a any) bool {
	t := reflect.TypeOf(a).String()
	_, ok := basicTypes[t]
	return ok
}

func isAMap(a any) bool {
	_, ok := a.(map[string]any)
	return ok
}

func isAnArray(a any) bool {
	_, ok := a.([]any)
	return ok
}

func redactMap(data *map[string]any) {
	for s, a := range *data {
		f, isRedacted := redactedFields[s]
		if isRedacted && isABasicType(a) {
			var err error
			(*data)[s], err = f(a)
			maybeDie(err)
		}
		if isAMap(a) {
			subMap := a.(map[string]any)
			redactMap(&subMap)
		}
		if isAnArray(a) {
			anys := a.([]any)
			for _, item := range anys {
				if isAMap(item) {
					subMap := item.(map[string]any)
					redactMap(&subMap)
				}
			}
		}
	}
}

func marshall(data map[string]any) []byte {
	bytes, err := json.Marshal(data)
	maybeDie(err)
	return bytes
}

func redact(bytes []byte) []byte {
	data := unmarshall(bytes)
	redactMap(&data)
	bytes = marshall(data)
	return bytes
}

func main() {
	// Register your transform function.
	// This is a good place to perform other setup too.
	transform.OnRecordWritten(doTransform)
}

// doTransform is where you read the record that was written, and then you can
// return new records that will be written to the output topic
func doTransform(e transform.WriteEvent) ([]transform.Record, error) {
	var result []transform.Record
	redacted := redact(e.Record().Value)
	var record = transform.Record{Headers: e.Record().Headers, Key: e.Record().Key, Value: redacted}
	result = append(result, record)
	return result, nil
}
