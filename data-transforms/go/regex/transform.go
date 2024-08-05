package main

import (
	"os"
	"regexp"
	"strings"

	"github.com/redpanda-data/redpanda/src/transform-sdk/go/transform"
)

var (
	re         *regexp.Regexp = nil
	checkValue bool           = false
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
	// setup the configuration
	pattern, ok := os.LookupEnv("PATTERN")
	if !ok {
		panic("Missing PATTERN variable")
	}
	re = regexp.MustCompile(pattern)
	mk, ok := os.LookupEnv("MATCH_VALUE")
	checkValue = ok && isTrueVar(mk)

	transform.OnRecordWritten(doRegexFilter)
}

func doRegexFilter(e transform.WriteEvent, w transform.RecordWriter) error {
	var b []byte
	if checkValue {
		b = e.Record().Value
	} else {
		b = e.Record().Key
	}
	if b == nil {
		return nil
	}
	pass := re.Match(b)
	if pass {
		return w.Write(e.Record())
	} else {
		return nil
	}
}
