package main

import (
	"bytes"
	"fmt"
	"github.com/bcicen/jstream"
	"github.com/redpanda-data/redpanda/src/transform-sdk/go"
	"io"
	"os"
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
	fn := func(e redpanda.WriteEvent) ([]redpanda.Record, error) {
		return doFlatten(e, buffer, delim)
	}

	redpanda.OnRecordWritten(fn)
}

// doTransform is where you read the record that was written, and then you can
// return new records that will be written to the output topic
func doFlatten(e redpanda.WriteEvent, buf *bytes.Buffer, delim string) ([]redpanda.Record, error) {
	record := e.Record()

	// Skip empty records.
	if record.Value == nil || len(record.Value) == 0 {
		return []redpanda.Record{}, nil
	}

	buf.Reset()

	r := bytes.NewReader(record.Value)
	err := Flatten(r, buf, delim)
	if err != nil {
		return []redpanda.Record{}, err
	}

	record.Value = buf.Bytes()
	return []redpanda.Record{record}, err
}

func Flatten(r io.Reader, w io.Writer, delim string) error {
	decoder := jstream.NewDecoder(r, 0)

	// Iterate over pointers to jstream.MetaValues.
	// n.b. this is a channel, btw
	for mv := range decoder.ObjectAsKVS().Stream() {
		kvs := mv.Value.(jstream.KVS)
		fmt.Fprintln(w, "{")
		for _, kv := range kvs {
			descend(w, kv, 0, kv.Key, delim, true)
		}
		fmt.Fprintln(w, "\n}")
	}
	return nil
}

func descend(w io.Writer, kv jstream.KV, depth int, key string, delim string, first bool) {
	if !first {
		fmt.Fprintln(w, ",")
	}

	switch kv.Value.(type) {
	case string:
		fmt.Fprintf(w, "  \"%s\": \"%s\"", key, kv.Value)
		break
	case []interface{}:
		// Somehow, this case doesn't match the jstream.KVS case.
		// If it did, this would all break :D
		fmt.Fprintf(w, "  \"%s\": [", key)
		for i, v := range kv.Value.([]interface{}) {
			if i > 0 {
				fmt.Fprintf(w, ", ")
			}
			switch v.(type) {
			case string:
				fmt.Fprintf(w, "\"%s\"", v)
				break
			default:
				fmt.Fprintf(w, "%v", v)
			}
		}
		fmt.Fprintf(w, "]")
		break
	case jstream.KVS:
		kvs := kv.Value.(jstream.KVS)
		nextFirst := true
		for _, kv := range kvs {
			new_key := key + delim + kv.Key
			descend(w, kv, depth+1, new_key, delim, nextFirst)
			nextFirst = false
		}
		// fallthrough
	default:
		if kv.Value != nil {
			fmt.Fprintf(w, "  \"%s\": %v", key, kv.Value)
		} else {
			fmt.Fprintf(w, "  \"%s\": null", key)
		}
	}
}
