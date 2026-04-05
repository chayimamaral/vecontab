package certseal

import (
	"bytes"
	"encoding/hex"
	"testing"
)

func TestSealOpenRoundTrip(t *testing.T) {
	key := make([]byte, KeySize)
	for i := range key {
		key[i] = byte(i)
	}
	plain := []byte("segredo-pfx-ou-senha")
	sealed, err := Seal(key, plain)
	if err != nil {
		t.Fatal(err)
	}
	got, err := Open(key, sealed)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, plain) {
		t.Fatalf("roundtrip: %q vs %q", got, plain)
	}
}

func TestParseKeyHex(t *testing.T) {
	key := make([]byte, KeySize)
	for i := range key {
		key[i] = 0xab
	}
	h := hex.EncodeToString(key)
	got, err := ParseKeyHex(h)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, key) {
		t.Fatal("hex decode mismatch")
	}
}
