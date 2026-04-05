// Package certseal cifra blobs sensíveis (PFX, senha) com AES-256-GCM.
// A chave mestra vem da aplicação (32 bytes); nunca commitar chaves.
package certseal

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"strings"
)

const (
	// KeySize é o tamanho exigido para AES-256.
	KeySize = 32
)

var (
	// ErrChaveInvalida indica tamanho ou formato de chave incorreto.
	ErrChaveInvalida = errors.New("chave AES-256 invalida: use 32 bytes ou 64 caracteres hexadecimais")
	// ErrDadosInvalidos indica payload truncado ou autenticação GCM falhou.
	ErrDadosInvalidos = errors.New("dados cifrados invalidos ou adulterados")
)

// ParseKeyHex decodifica 64 caracteres hex (32 bytes) para uso como chave AES-256.
func ParseKeyHex(s string) ([]byte, error) {
	s = strings.TrimSpace(s)
	if len(s) != KeySize*2 {
		return nil, ErrChaveInvalida
	}
	b, err := hex.DecodeString(s)
	if err != nil || len(b) != KeySize {
		return nil, ErrChaveInvalida
	}
	return b, nil
}

// Seal cifra plaintext com AES-256-GCM. O retorno é nonce || ciphertext||tag (formato padrão do Seal).
func Seal(key, plaintext []byte) ([]byte, error) {
	if len(key) != KeySize {
		return nil, ErrChaveInvalida
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("aes: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("gcm: %w", err)
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, fmt.Errorf("nonce: %w", err)
	}
	ct := gcm.Seal(nil, nonce, plaintext, nil)
	out := make([]byte, 0, len(nonce)+len(ct))
	out = append(out, nonce...)
	out = append(out, ct...)
	return out, nil
}

// Open decifra o blob produzido por Seal.
func Open(key, sealed []byte) ([]byte, error) {
	if len(key) != KeySize {
		return nil, ErrChaveInvalida
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("aes: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("gcm: %w", err)
	}
	ns := gcm.NonceSize()
	if len(sealed) < ns {
		return nil, ErrDadosInvalidos
	}
	nonce, ct := sealed[:ns], sealed[ns:]
	plain, err := gcm.Open(nil, nonce, ct, nil)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrDadosInvalidos, err)
	}
	return plain, nil
}
