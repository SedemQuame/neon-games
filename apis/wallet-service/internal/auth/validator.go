package auth

import (
	"crypto/rsa"
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/golang-jwt/jwt/v5"
)

// ErrMissingToken signals that no bearer token was supplied.
var ErrMissingToken = errors.New("missing bearer token")

// Claims captures the minimal fields we expect on Glory Grid access tokens.
type Claims struct {
	UserID string `json:"uid"`
	Role   string `json:"role"`
	jwt.RegisteredClaims
}

// Validator verifies RS256 JWTs emitted by the auth service.
type Validator struct {
	publicKey *rsa.PublicKey
	issuer    string
}

// NewValidator loads the RSA public key from disk.
func NewValidator(publicKeyPath, issuer string) (*Validator, error) {
	data, err := os.ReadFile(publicKeyPath)
	if err != nil {
		return nil, fmt.Errorf("read public key: %w", err)
	}
	key, err := jwt.ParseRSAPublicKeyFromPEM(data)
	if err != nil {
		return nil, fmt.Errorf("parse public key: %w", err)
	}
	return &Validator{
		publicKey: key,
		issuer:    issuer,
	}, nil
}

// Parse validates a raw JWT string and returns the embedded claims.
func (v *Validator) Parse(token string) (*Claims, error) {
	token = strings.TrimSpace(token)
	if token == "" {
		return nil, ErrMissingToken
	}
	opts := []jwt.ParserOption{
		jwt.WithValidMethods([]string{jwt.SigningMethodRS256.Alg()}),
	}
	if v.issuer != "" {
		opts = append(opts, jwt.WithIssuer(v.issuer))
	}
	parsed, err := jwt.ParseWithClaims(token, &Claims{}, func(t *jwt.Token) (interface{}, error) {
		return v.publicKey, nil
	}, opts...)
	if err != nil {
		return nil, err
	}
	claims, ok := parsed.Claims.(*Claims)
	if !ok || !parsed.Valid {
		return nil, errors.New("invalid token claims")
	}
	if claims.UserID == "" {
		claims.UserID = claims.Subject
	}
	if claims.UserID == "" {
		return nil, errors.New("user id missing in token")
	}
	return claims, nil
}

// FromHeader extracts the bearer token from an Authorization header and validates it.
func (v *Validator) FromHeader(header string) (*Claims, error) {
	token := extractToken(header)
	if token == "" {
		return nil, ErrMissingToken
	}
	return v.Parse(token)
}

// FromString validates a token string directly (useful for query params).
func (v *Validator) FromString(token string) (*Claims, error) {
	return v.Parse(token)
}

func extractToken(header string) string {
	header = strings.TrimSpace(header)
	if header == "" {
		return ""
	}
	if strings.HasPrefix(header, "Bearer ") {
		return strings.TrimSpace(strings.TrimPrefix(header, "Bearer "))
	}
	return header
}
