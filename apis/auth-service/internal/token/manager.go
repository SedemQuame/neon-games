package token

import (
	"crypto/rsa"
	"fmt"
	"os"
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
	bytes, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return jwt.ParseRSAPrivateKeyFromPEM(bytes)
}

func loadPublicKey(path string) (*rsa.PublicKey, error) {
	bytes, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return jwt.ParseRSAPublicKeyFromPEM(bytes)
}
