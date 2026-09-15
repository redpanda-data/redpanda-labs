package wire

import (
	"errors"
	"testing"
)

func TestRoundTrip(t *testing.T) {
	body := []byte{1, 2, 3}
	id, out, err := Decode(Encode(1234, body))
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if id != 1234 {
		t.Fatalf("schema id = %d, want 1234", id)
	}
	if string(out) != string(body) {
		t.Fatalf("body = %v, want %v", out, body)
	}
}

// The two ways a value can be wrong, both of which a consumer must survive:
// plain JSON someone produced with rpk, and a truncated value.
func TestDecodeRejectsValuesThatAreNotRegistryEncoded(t *testing.T) {
	for _, tc := range []struct {
		name  string
		value []byte
	}{
		{"plain json", []byte(`{"fixture_id":"fx-1"}`)},
		{"too short", []byte{0, 0, 1}},
		{"empty", nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, _, err := Decode(tc.value); !errors.Is(err, ErrNotRegistryEncoded) {
				t.Fatalf("err = %v, want ErrNotRegistryEncoded", err)
			}
		})
	}
}
