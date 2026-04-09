package token

import (
	"crypto/rsa"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Claims represents the JWT payload issued by the auth service.
type Claims struct {
	UserID string `json:"uid"`
	Role   string `json:"role"`
	jwt.RegisteredClaims
}

// Manager is responsible for issuing and validating JWT access tokens.
type Manager struct {
	privateKey *rsa.PrivateKey
	publicKey  *rsa.PublicKey
	issuer     string
	accessTTL  time.Duration
}

// NewManager loads RSA keys from disk and returns a configured Manager.
func NewManager(privateKeyPath, publicKeyPath, issuer string, accessTTL time.Duration) (*Manager, error) {
	priv, err := loadPrivateKey(privateKeyPath)
	if err != nil {
		return nil, fmt.Errorf("load private key: %w", err)
	}
	pub, err := loadPublicKey(publicKeyPath)
	if err != nil {
		return nil, fmt.Errorf("load public key: %w", err)
	}
	if issuer == "" {
		issuer = "gamehub-auth"
	}
	if accessTTL <= 0 {
		accessTTL = 15 * time.Minute
	}
	return &Manager{
		privateKey: priv,
		publicKey:  pub,
		issuer:     issuer,
		accessTTL:  accessTTL,
	}, nil
}

// IssueAccessToken signs and returns a JWT for the given user and role.
func (m *Manager) IssueAccessToken(userID, role string) (string, error) {
	now := time.Now()
	claims := Claims{
		UserID: userID,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			Issuer:    m.issuer,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(m.accessTTL)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	return token.SignedString(m.privateKey)
}

// Parse validates an incoming JWT string and returns the embedded claims.
func (m *Manager) Parse(tokenString string) (*Claims, error) {
	parsed, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(t *jwt.Token) (interface{}, error) {
		return m.publicKey, nil
	}, jwt.WithValidMethods([]string{jwt.SigningMethodRS256.Alg()}))
	if err != nil {
		return nil, err
	}
	claims, ok := parsed.Claims.(*Claims)
	if !ok || !parsed.Valid {
		return nil, fmt.Errorf("invalid token claims")
	}
	return claims, nil
}

func loadPrivateKey(path string) (*rsa.PrivateKey, error) {
	if pem := pemFromEnv("JWT_PRIVATE_KEY_PEM"); pem != "" {
		return jwt.ParseRSAPrivateKeyFromPEM([]byte(pem))
	}
	if strings.TrimSpace(path) == "" {
		return nil, fmt.Errorf("JWT_PRIVATE_KEY_PEM or JWT_PRIVATE_KEY_PATH must be set")
	}
	bytes, err := readPEMFile(path)
	if err != nil {
		return nil, fmt.Errorf("set JWT_PRIVATE_KEY_PEM or point JWT_PRIVATE_KEY_PATH to a readable PEM file: %w", err)
	}
	return jwt.ParseRSAPrivateKeyFromPEM(bytes)
}

func loadPublicKey(path string) (*rsa.PublicKey, error) {
	if pem := pemFromEnv("JWT_PUBLIC_KEY_PEM"); pem != "" {
		return jwt.ParseRSAPublicKeyFromPEM([]byte(pem))
	}
	if strings.TrimSpace(path) == "" {
		return nil, fmt.Errorf("JWT_PUBLIC_KEY_PEM or JWT_PUBLIC_KEY_PATH must be set")
	}
	bytes, err := readPEMFile(path)
	if err != nil {
		return nil, fmt.Errorf("set JWT_PUBLIC_KEY_PEM or point JWT_PUBLIC_KEY_PATH to a readable PEM file: %w", err)
	}
	return jwt.ParseRSAPublicKeyFromPEM(bytes)
}

func pemFromEnv(key string) string {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return ""
	}
	return strings.ReplaceAll(raw, `\n`, "\n")
}

func readPEMFile(path string) ([]byte, error) {
	path = strings.TrimSpace(path)
	if path == "" {
		return nil, fmt.Errorf("no PEM file path configured")
	}

	data, err := os.ReadFile(path)
	if err == nil {
		return data, nil
	}

	info, statErr := os.Stat(path)
	if statErr != nil || !info.IsDir() {
		return nil, err
	}

	entries, err := os.ReadDir(path)
	if err != nil {
		return nil, err
	}

	preferredName := filepath.Base(filepath.Clean(path))
	var firstPEM string
	var loneFile string

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		fullPath := filepath.Join(path, entry.Name())
		if entry.Name() == preferredName {
			return os.ReadFile(fullPath)
		}

		if strings.HasSuffix(strings.ToLower(entry.Name()), ".pem") && firstPEM == "" {
			firstPEM = fullPath
		}

		if loneFile == "" {
			loneFile = fullPath
		} else {
			loneFile = "-"
		}
	}

	if firstPEM != "" {
		return os.ReadFile(firstPEM)
	}
	if loneFile != "" && loneFile != "-" {
		return os.ReadFile(loneFile)
	}

	return nil, fmt.Errorf("%s is a directory and does not contain a readable PEM file", path)
}
