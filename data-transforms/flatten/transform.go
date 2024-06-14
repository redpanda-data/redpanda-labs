package main

import (
	"bytes"
	"fmt"
	"io"
	"os"

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
		for _, kv := range kvs {
			descend(w, kv, 0, kv.Key, delim)
		}
		fmt.Fprintln(w, "\n}")
	}
	return nil
}

func descend(w io.Writer, kv jstream.KV, depth int, key string, delim string) {

	switch kv.Value.(type) {
	case string:
		fmt.Fprintf(w, "  \"%s\": \"%s\",\n", key, kv.Value)
		return
	case []interface{}:
		// Somehow, this case doesn't match the jstream.KVS case.
		// If it did, this would all break :D
		fmt.Fprintf(w, "  \"%s\": [", key)
		for _, v := range kv.Value.([]interface{}) {
			switch v.(type) {
			case string:
				fmt.Fprintf(w, "\"%s\"", v)
				break
			default:
				fmt.Fprintf(w, "%v", v)
			}
		}
		fmt.Fprintf(w, "]")
		return
	case jstream.KVS:
		kvs := kv.Value.(jstream.KVS)
		for _, kv := range kvs {
			new_key := key + delim + kv.Key
			descend(w, kv, depth+1, new_key, delim)
		}
		// fallthrough
	default:
		if kv.Value != nil {
			fmt.Fprintf(w, "  \"%s\": %v,\n", key, kv.Value)
		} else {
			fmt.Fprintf(w, "  \"%s\": null,\n", key)
		}
	}
}
