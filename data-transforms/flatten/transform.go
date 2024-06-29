package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/bcicen/jstream"
	"github.com/redpanda-data/redpanda/src/transform-sdk/go/transform"
)

const DELIM_KEY = "RP_FLATTEN_DELIM"
const DELIM_DEFAULT = "."

func main() {
	delim, present := os.LookupEnv(DELIM_KEY)
	if !present {
		delim = DELIM_DEFAULT
	}
	fmt.Println("using delimitter: ", delim)

	buffer := bytes.NewBuffer(make([]byte, 1024))
	fn := func(e transform.WriteEvent, w transform.RecordWriter) error {
		return doFlatten(e, w, buffer, delim)
	}

	transform.OnRecordWritten(fn)
}

// doTransform is where you read the record that was written, and then you can
// return new records that will be written to the output topic
func doFlatten(e transform.WriteEvent, w transform.RecordWriter, buf *bytes.Buffer, delim string) error {
	record := e.Record()

	// Skip empty records.
	if record.Value == nil || len(record.Value) == 0 {
		return nil
	}

	buf.Reset()

	r := bytes.NewReader(record.Value)
	err := Flatten(r, buf, delim)
	if err != nil {
		return err
	}

	record.Value = buf.Bytes()
	return w.Write(record)
}

func Flatten(r io.Reader, w io.Writer, delim string) error {
	decoder := jstream.NewDecoder(r, 0)

	// Iterate over pointers to jstream.MetaValues.
	// n.b. this is a channel, btw
	for mv := range decoder.ObjectAsKVS().Stream() {
		kvs := mv.Value.(jstream.KVS)
		fmt.Fprintln(w, "{")
		for index, kv := range kvs {
			descend(w, kv, 0, kv.Key, delim)
			handleLastElement(w, len(kvs), index, ",\n")
		}
		fmt.Fprintln(w, "\n}")
	}
	return nil
}

func descend(w io.Writer, kv jstream.KV, depth int, key string, delim string) {

	switch kv.Value.(type) {
	case string:
		stringValue := kv.Value.(string)
		stringValue = strings.Replace(stringValue, "\n", " ", -1)
		fmt.Fprintf(w, "  \"%s\": \"%s\"", key, stringValue)
		return
	case []interface{}:
		isNodeFlattened := flattenListOfJsonObjects(w, kv, depth, key, delim)
		if isNodeFlattened {
			return
		}
		fmt.Fprintf(w, "  \"%s\": [", key)
		for index, v := range kv.Value.([]interface{}) {
			switch v.(type) {
			case string:
				stringValue := v.(string)
				stringValue = strings.Replace(stringValue, "\n", " ", -1)
				fmt.Fprintf(w, "\"%s\"", stringValue)
			default:
				fmt.Fprintf(w, "%v", v)
			}
			handleLastElement(w, len(kv.Value.([]interface{})), index, ", ")
		}
		fmt.Fprintf(w, "]")
	case jstream.KVS:
		kvs := kv.Value.(jstream.KVS)
		if len(kvs) == 0 {
			fmt.Fprintf(w, "  \"%s\": {}", key)
			return
		}

		for index, kv := range kvs {
			new_key := key + delim + kv.Key
			descend(w, kv, depth+1, new_key, delim)
			handleLastElement(w, len(kvs), index, ",\n")
		}
	default:
		if kv.Value != nil {
			fmt.Fprintf(w, "  \"%s\": %v", key, kv.Value)
		} else {
			fmt.Fprintf(w, "  \"%s\": null", key)
		}
	}
}


func handleLastElement(w io.Writer, listSize int, index int, endingString string){
	var isLastSubElementLocal = listSize - 1 == index
	if ! isLastSubElementLocal {
		fmt.Fprintf(w, "%s", endingString)
	}
}


func flattenListOfJsonObjects(w io.Writer, kv jstream.KV, depth int, key string, delim string) bool {
	isNodeFlattened := false
	for parent_index, v := range kv.Value.([]interface{}) {
		switch v.(type) {
		case jstream.KVS:
			isNodeFlattened = true
			kvs := v.(jstream.KVS)

			for index, kv := range kvs {
				new_key := key + delim + fmt.Sprint(parent_index) + delim + kv.Key
				descend(w, kv, depth+1, new_key, delim)
				handleLastElement(w, len(kvs), index, ",\n")
			}
			handleLastElement(w, len(kv.Value.([]interface{})), parent_index, ",\n")

		default:
			return isNodeFlattened
		}
	}
	return isNodeFlattened
}
