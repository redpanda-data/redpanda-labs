// Package wire encodes and decodes the five bytes Schema Registry clients put
// in front of every record value.
//
// The format is fixed and worth knowing, because it is what lets one topic
// hold records written under two schema versions at once: byte 0 is a magic
// 0x00, bytes 1 to 4 are the schema ID big-endian, and the Avro body follows.
// A consumer reads the ID first, fetches that exact schema, and decodes with
// it. Nothing about the bytes says which version is "current".
package wire

import (
	"encoding/binary"
	"errors"
	"fmt"
)

// HeaderLen is the magic byte plus the four ID bytes.
const HeaderLen = 5

// ErrNotRegistryEncoded is returned for a value that does not begin with the
// magic byte: something wrote to the topic without the registry.
var ErrNotRegistryEncoded = errors.New("value is not Schema Registry encoded (no 0x00 magic byte)")

// tag::encode[]
// Encode prefixes an Avro body with the schema ID it was written under.
func Encode(schemaID int, body []byte) []byte {
	out := make([]byte, HeaderLen+len(body))
	out[0] = 0
	binary.BigEndian.PutUint32(out[1:5], uint32(schemaID))
	copy(out[HeaderLen:], body)
	return out
}

// Decode splits a record value into the schema ID and the Avro body.
func Decode(value []byte) (int, []byte, error) {
	if len(value) < HeaderLen {
		return 0, nil, fmt.Errorf("%w: %d bytes", ErrNotRegistryEncoded, len(value))
	}
	if value[0] != 0 {
		return 0, nil, fmt.Errorf("%w: first byte is 0x%02x", ErrNotRegistryEncoded, value[0])
	}
	return int(binary.BigEndian.Uint32(value[1:5])), value[HeaderLen:], nil
}

// end::encode[]
