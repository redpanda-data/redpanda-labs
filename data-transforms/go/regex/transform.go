package main

import (
	"log"
	"os"
	"regexp"
	"strings"

	"github.com/redpanda-data/redpanda/src/transform-sdk/go/transform"
)

var (
	re         *regexp.Regexp
	checkValue bool
)

func isTrueVar(v string) bool {
	switch strings.ToLower(v) {
	case "yes", "ok", "1", "true":
		return true
	default:
		return false
	}
}

func main() {
	// Optionally configure log format, prefix, or flags
	log.SetPrefix("[regex-transform] ")
	log.SetFlags(log.Ldate | log.Ltime | log.LUTC | log.Lmicroseconds)

	log.Println("Starting transform...")

	pattern, ok := os.LookupEnv("PATTERN")
	if !ok {
		log.Fatal("Missing PATTERN environment variable")
	}
	log.Printf("Using PATTERN: %q\n", pattern)
	re = regexp.MustCompile(pattern)

	mk, ok := os.LookupEnv("MATCH_VALUE")
	checkValue = ok && isTrueVar(mk)
	log.Printf("MATCH_VALUE set to: %t\n", checkValue)

	log.Println("Initialization complete, waiting for records...")

	transform.OnRecordWritten(doRegexFilter)
}

func doRegexFilter(e transform.WriteEvent, w transform.RecordWriter) error {
	var dataToCheck []byte
	if checkValue {
		dataToCheck = e.Record().Value
		log.Printf("Checking record value: %s\n", string(dataToCheck))
	} else {
		dataToCheck = e.Record().Key
		log.Printf("Checking record key: %s\n", string(dataToCheck))
	}

	if dataToCheck == nil {
		log.Println("Record has no key/value to check, skipping.")
		return nil
	}

	pass := re.Match(dataToCheck)
	if pass {
		log.Printf("Record matched pattern, passing through. Key: %s, Value: %s\n", string(e.Record().Key), string(e.Record().Value))
		return w.Write(e.Record())
	} else {
		log.Printf("Record did not match pattern, dropping. Key: %s, Value: %s\n", string(e.Record().Key), string(e.Record().Value))
		return nil
	}
}
