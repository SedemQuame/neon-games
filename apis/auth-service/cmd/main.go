package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log"
	"math/big"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"golang.org/x/crypto/argon2"

	"gamehub/auth-service/internal/config"
	"gamehub/auth-service/internal/mailer"
	"gamehub/auth-service/internal/token"
)

var (
	db         *mongo.Database
	cfg        *config.Config
	rdb        *redis.Client
	jwtManager *token.Manager
	mailClient *mailer.Client

	usernameSanitizer  = regexp.MustCompile(`[^a-z0-9]+`)
	googleHTTPClient   = &http.Client{Timeout: 10 * time.Second}
	firebaseHTTPClient = &http.Client{Timeout: 10 * time.Second}
	firebaseCertCache  = &firebasePublicKeyCache{}
	allowAllOrigins    bool
	allowedOriginSet   map[string]struct{}
)

const (
	otpLength           = 6
	argonTime    uint32 = 1
	argonMemory  uint32 = 64 * 1024
	argonThreads uint8  = 4
	argonKeyLen  uint32 = 32

	firebasePublicKeysEndpoint = "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"
	defaultFirebaseCertTTL     = 60 * time.Minute
)

type ctxKey string

const ctxUserKey ctxKey = "auth_user"

type refreshSession struct {
	UserID string `json:"userId"`
	Role   string `json:"role"`
}

type firebasePublicKeyCache struct {
	mu        sync.RWMutex
	keys      map[string]*rsa.PublicKey
	expiresAt time.Time
}

func main() {
	log.SetOutput(os.Stdout)

	cfg = config.Load()
	configureAllowedOrigins(cfg.AllowedOrigins)
	mailClient = mailer.New(cfg.ResendAPIKey, cfg.EmailFrom, cfg.PasswordResetURL)

	// --- MongoDB ---
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	client, err := mongo.Connect(ctx, options.Client().ApplyURI(cfg.MongoURI))
	if err != nil {
		log.Fatalf("MongoDB connect: %v", err)
	}
	if err := client.Ping(ctx, nil); err != nil {
		log.Fatalf("MongoDB ping: %v", err)
	}
	defer client.Disconnect(context.Background())
	db = client.Database("gamehub")

	setupIndexes()

	// --- Redis (refresh tokens, rate limiting, etc.) ---
	rdb = redis.NewClient(&redis.Options{
		Addr:     cfg.RedisAddr,
		Password: cfg.RedisPassword,
	})
	if err := rdb.Ping(context.Background()).Err(); err != nil {
		log.Fatalf("Redis ping: %v", err)
	}
	defer rdb.Close()

	// --- JWT Manager ---
	jwtManager, err = token.NewManager(cfg.JWTPrivateKey, cfg.JWTPublicKey, cfg.JWTIssuer, cfg.AccessTTL)
	if err != nil {
		log.Fatalf("token manager init: %v", err)
	}

	// --- HTTP Router ---
	mux := http.NewServeMux()

	// CORS + JSON middleware wrapper
	handler := loggingMiddleware(corsMiddleware(mux))

	registerRoute(mux, http.MethodGet, "/health", handleHealth)

	// Phone + OTP
	registerRoute(mux, http.MethodPost, "/api/v1/auth/phone/request-otp", handleRequestOTP)
	registerRoute(mux, http.MethodPost, "/api/v1/auth/phone/verify-otp", handleVerifyOTP)

	// Firebase Auth token exchange
	registerRoute(mux, http.MethodPost, "/api/v1/auth/firebase/login", handleFirebaseLogin)

	// Google Sign-In
	registerRoute(mux, http.MethodPost, "/api/v1/auth/google/login", handleGoogleLogin)

	// Email + Password
	registerRoute(mux, http.MethodPost, "/api/v1/auth/email/register", handleEmailRegister)
	registerRoute(mux, http.MethodPost, "/api/v1/auth/email/login", handleEmailLogin)
	registerRoute(mux, http.MethodPost, "/api/v1/auth/email/forgot", handleEmailForgotPassword)
	registerRoute(mux, http.MethodPost, "/api/v1/auth/email/reset", handleEmailResetPassword)

	// Guest
	registerRoute(mux, http.MethodPost, "/api/v1/auth/guest/start", handleGuestStart)

	// Token management
	registerRoute(mux, http.MethodPost, "/api/v1/auth/refresh", handleRefreshToken)
	registerRoute(mux, http.MethodPost, "/api/v1/auth/logout", handleLogout)

	// Profile (requires auth header)
	registerRoute(mux, http.MethodGet, "/api/v1/auth/me", requireAuth(handleGetProfile))
	registerRoute(mux, http.MethodPost, "/api/v1/auth/kyc/initiate", requireAuth(handleKYCInitiate))

	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      handler,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("✅ Auth service running on :%s (env=%s)", cfg.Port, cfg.AppEnv)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server error: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
	<-quit
	log.Println("Shutting down auth-service...")
	_ = srv.Shutdown(context.Background())
}

// ============================================================
// HEALTH
// ============================================================

func handleHealth(w http.ResponseWriter, r *http.Request) {
	respondJSON(w, 200, map[string]string{"status": "ok", "service": "auth-service"})
}

// ============================================================
// PHONE + OTP
// ============================================================

func handleRequestOTP(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var body struct {
		Phone string `json:"phone"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Phone == "" {
		respondError(w, 400, "phone is required")
		return
	}

	// Generate 6-digit OTP
	code := generateOTP(otpLength)

	// Store in MongoDB with TTL
	ttl, err := time.ParseDuration(cfg.OTPTTLMinutes + "m")
	if err != nil || ttl <= 0 {
		ttl = 5 * time.Minute
	}
	_, err = db.Collection("otps").ReplaceOne(
		ctx,
		bson.M{"phone": body.Phone},
		bson.M{
			"phone":     body.Phone,
			"code":      hashOTP(code),
			"expiresAt": time.Now().Add(ttl),
			"used":      false,
		},
		options.Replace().SetUpsert(true),
	)
	if err != nil {
		respondError(w, 500, "could not persist OTP")
		return
	}

	// In development: log instead of actually calling Hubtel SMS
	if cfg.AppEnv == "development" {
		log.Printf("🔑 OTP for %s: %s", body.Phone, code)
		respondJSON(w, 200, map[string]interface{}{
			"message": "OTP sent (dev: check server logs)",
			"dev_otp": code, // Only returned in development!
		})
		return
	}

	// TODO: Call Hubtel SMS API to deliver the code
	// hubtelSMS.Send(body.Phone, "Your Glory Grid OTP: "+code)

	respondJSON(w, 200, map[string]string{"message": "OTP sent to " + body.Phone})
}

func handleVerifyOTP(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var body struct {
		Phone string `json:"phone"`
		Code  string `json:"code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		respondError(w, 400, "invalid request")
		return
	}

	var otpDoc bson.M
	err := db.Collection("otps").FindOne(ctx, bson.M{
		"phone":     body.Phone,
		"used":      false,
		"expiresAt": bson.M{"$gt": time.Now()},
	}).Decode(&otpDoc)
	if err != nil {
		respondError(w, 401, "OTP not found or expired")
		return
	}

	storedHash, ok := otpDoc["code"].(string)
	if !ok || storedHash != hashOTP(body.Code) {
		respondError(w, 401, "invalid OTP")
		return
	}

	// Mark OTP as used
	_, _ = db.Collection("otps").UpdateOne(ctx,
		bson.M{"phone": body.Phone},
		bson.M{"$set": bson.M{"used": true}},
	)

	// Upsert user
	user, err := upsertUserByPhone(ctx, body.Phone)
	if err != nil {
		respondError(w, 500, "failed to prepare user")
		return
	}
	userID, err := extractUserID(user)
	if err != nil {
		respondError(w, 500, "user id missing")
		return
	}

	// Trigger async JIT wallet generation (BTC, ETH, USDT)
	triggerWalletGeneration(userID)

	// Issue tokens
	accessToken, refreshToken, err := issueTokenPair(ctx, userID, "user")
	if err != nil {
		respondError(w, 500, "failed to issue tokens")
		return
	}

	respondJSON(w, 200, map[string]interface{}{
		"accessToken":  accessToken,
		"refreshToken": refreshToken,
		"user":         sanitizeUser(user),
	})
}

// ============================================================
// FIREBASE AUTH
// ============================================================

type firebaseTokenClaims struct {
	Email         string `json:"email"`
	EmailVerified bool   `json:"email_verified"`
	Name          string `json:"name"`
	Picture       string `json:"picture"`
	Firebase      struct {
		SignInProvider string              `json:"sign_in_provider"`
		Identities     map[string][]string `json:"identities"`
	} `json:"firebase"`
	jwt.RegisteredClaims
}

type firebaseIdentity struct {
	UID          string
	Email        string
	FullName     string
	AvatarURL    string
	ProviderRaw  string
	ProviderName string
	IsGuest      bool
}

func handleFirebaseLogin(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if strings.TrimSpace(cfg.FirebaseProjectID) == "" {
		respondError(w, 503, "firebase auth is not configured")
		return
	}

	var body struct {
		IDToken string `json:"idToken"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		respondError(w, 400, "invalid request")
		return
	}
	idToken := strings.TrimSpace(body.IDToken)
	if idToken == "" {
		respondError(w, 400, "idToken is required")
		return
	}

	claims, err := verifyFirebaseIDToken(ctx, idToken)
	if err != nil {
		log.Printf("firebase token validation failed: %v", err)
		respondError(w, 401, "invalid firebase identity token")
		return
	}

	identity := firebaseIdentity{
		UID:          strings.TrimSpace(claims.Subject),
		Email:        strings.ToLower(strings.TrimSpace(claims.Email)),
		FullName:     strings.TrimSpace(claims.Name),
		AvatarURL:    strings.TrimSpace(claims.Picture),
		ProviderRaw:  strings.TrimSpace(claims.Firebase.SignInProvider),
		ProviderName: normalizeFirebaseProvider(claims.Firebase.SignInProvider),
		IsGuest:      strings.EqualFold(strings.TrimSpace(claims.Firebase.SignInProvider), "anonymous"),
	}

	user, shouldProvisionWallets, role, err := upsertUserByFirebase(ctx, identity)
	if err != nil {
		respondError(w, 500, "failed to prepare user")
		return
	}
	userID, err := extractUserID(user)
	if err != nil {
		respondError(w, 500, "user id missing")
		return
	}
	if shouldProvisionWallets {
		triggerWalletGeneration(userID)
	}

	accessToken, refreshToken, err := issueTokenPair(ctx, userID, role)
	if err != nil {
		respondError(w, 500, "failed to issue tokens")
		return
	}

	respondJSON(w, 200, map[string]interface{}{
		"accessToken":  accessToken,
		"refreshToken": refreshToken,
		"user":         sanitizeUser(user),
	})
}

// ============================================================
// GOOGLE SIGN-IN
// ============================================================

type googleTokenInfo struct {
	Audience      string `json:"aud"`
	Email         string `json:"email"`
	EmailVerified string `json:"email_verified"`
	ExpiresAtUnix string `json:"exp"`
	Issuer        string `json:"iss"`
	FullName      string `json:"name"`
	AvatarURL     string `json:"picture"`
	Subject       string `json:"sub"`
}

func handleGoogleLogin(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if len(cfg.GoogleClientIDs) == 0 {
		respondError(w, 503, "google sign-in is not configured")
		return
	}

	var body struct {
		IDToken string `json:"idToken"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		respondError(w, 400, "invalid request")
		return
	}
	idToken := strings.TrimSpace(body.IDToken)
	if idToken == "" {
		respondError(w, 400, "idToken is required")
		return
	}

	claims, err := verifyGoogleIDToken(ctx, idToken)
	if err != nil {
		log.Printf("google token validation failed: %v", err)
		respondError(w, 401, "invalid google identity token")
		return
	}

	user, shouldProvisionWallets, err := upsertUserByGoogle(ctx, claims)
	if err != nil {
		respondError(w, 500, "failed to prepare user")
		return
	}
	userID, err := extractUserID(user)
	if err != nil {
		respondError(w, 500, "user id missing")
		return
	}
	if shouldProvisionWallets {
		triggerWalletGeneration(userID)
	}

	accessToken, refreshToken, err := issueTokenPair(ctx, userID, "user")
	if err != nil {
		respondError(w, 500, "failed to issue tokens")
		return
	}

	respondJSON(w, 200, map[string]interface{}{
		"accessToken":  accessToken,
		"refreshToken": refreshToken,
		"user":         sanitizeUser(user),
	})
}

// ============================================================
// EMAIL + PASSWORD
// ============================================================

func handleEmailRegister(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var body struct {
		Username string `json:"username"`
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Email == "" || body.Password == "" {
		respondError(w, 400, "email and password are required")
		return
	}

	// Check if email already exists
	count, err := db.Collection("users").CountDocuments(ctx, bson.M{"email": body.Email})
	if count > 0 {
		respondError(w, 409, "email already registered")
		return
	}

	hash, err := hashPassword(body.Password)
	if err != nil {
		respondError(w, 500, "failed to hash password")
		return
	}
	now := time.Now()
	doc := bson.M{
		"username":      body.Username,
		"email":         body.Email,
		"passwordHash":  hash,
		"authProviders": []string{"email"},
		"isGuest":       false,
		"kycStatus":     "NONE",
		"tier":          "BRONZE",
		"createdAt":     now,
		"updatedAt":     now,
	}
	res, err := db.Collection("users").InsertOne(ctx, doc)
	if err != nil {
		respondError(w, 500, "failed to create user")
		return
	}

	userID := res.InsertedID.(primitive.ObjectID).Hex()

	// Trigger async JIT wallet generation (BTC, ETH, USDT)
	triggerWalletGeneration(userID)

	accessToken, refreshToken, err := issueTokenPair(ctx, userID, "user")
	if err != nil {
		respondError(w, 500, "failed to issue tokens")
		return
	}

	doc["_id"] = res.InsertedID
	respondJSON(w, 201, map[string]interface{}{
		"accessToken":  accessToken,
		"refreshToken": refreshToken,
		"user":         sanitizeUser(doc),
	})
}

func handleEmailLogin(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var body struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		respondError(w, 400, "invalid request")
		return
	}

	var user bson.M
	err := db.Collection("users").FindOne(ctx, bson.M{"email": body.Email}).Decode(&user)
	if err != nil {
		respondError(w, 401, "invalid email or password")
		return
	}

	storedHash, _ := user["passwordHash"].(string)
	if !verifyPassword(body.Password, storedHash) {
		respondError(w, 401, "invalid email or password")
		return
	}

	userID, err := extractUserID(user)
	if err != nil {
		respondError(w, 500, "user id missing")
		return
	}
	accessToken, refreshToken, err := issueTokenPair(ctx, userID, "user")
	if err != nil {
		respondError(w, 500, "failed to issue tokens")
		return
	}

	respondJSON(w, 200, map[string]interface{}{
		"accessToken":  accessToken,
		"refreshToken": refreshToken,
		"user":         sanitizeUser(user),
	})
}

func handleEmailForgotPassword(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var body struct {
		Email string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		respondError(w, 400, "invalid request payload")
		return
	}
	email := strings.TrimSpace(strings.ToLower(body.Email))
	if email == "" {
		respondError(w, 400, "email is required")
		return
	}

	var user bson.M
	err := db.Collection("users").FindOne(ctx, bson.M{"email": email}).Decode(&user)
	if err != nil {
		// Always respond with 202 to avoid leaking account existence
		time.Sleep(300 * time.Millisecond)
		respondJSON(w, 202, map[string]string{
			"message": "If an account exists, a reset email will arrive shortly.",
		})
		return
	}
	userID, err := extractUserID(user)
	if err != nil {
		respondError(w, 500, "user id missing")
		return
	}
	token, err := generateSecureToken(48)
	if err != nil {
		respondError(w, 500, "unable to generate reset token")
		return
	}
	if err := storePasswordResetToken(ctx, userID, email, token); err != nil {
		log.Printf("reset token store failed: %v", err)
		respondError(w, 500, "failed to enqueue reset email")
		return
	}
	if err := mailClient.SendPasswordReset(ctx, email, token); err != nil {
		log.Printf("password reset email error: %v", err)
		respondError(w, 500, "failed to send reset email")
		return
	}
	respondJSON(w, 202, map[string]string{
		"message": "If an account exists, a reset email will arrive shortly.",
	})
}

func handleEmailResetPassword(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var body struct {
		Token    string `json:"token"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		respondError(w, 400, "invalid request")
		return
	}
	if body.Token == "" || body.Password == "" {
		respondError(w, 400, "token and password are required")
		return
	}
	resetDoc, err := consumePasswordResetToken(ctx, body.Token)
	if err != nil {
		respondError(w, 400, err.Error())
		return
	}
	userIDHex, _ := resetDoc["userId"].(string)
	if userIDHex == "" {
		respondError(w, 400, "invalid reset token")
		return
	}
	oid, err := primitive.ObjectIDFromHex(userIDHex)
	if err != nil {
		respondError(w, 400, "invalid reset token")
		return
	}
	hash, err := hashPassword(body.Password)
	if err != nil {
		respondError(w, 500, "failed to hash password")
		return
	}
	_, err = db.Collection("users").UpdateByID(ctx, oid, bson.M{
		"$set": bson.M{
			"passwordHash": hash,
			"updatedAt":    time.Now(),
		},
	})
	if err != nil {
		respondError(w, 500, "failed to update password")
		return
	}
	respondJSON(w, 200, map[string]string{
		"message": "Password updated. You can now log in with the new credentials.",
	})
}

// ============================================================
// GUEST
// ============================================================

func handleGuestStart(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	now := time.Now()
	doc := bson.M{
		"isGuest":       true,
		"authProviders": []string{"guest"},
		"kycStatus":     "NONE",
		"tier":          "BRONZE",
		"createdAt":     now,
		"updatedAt":     now,
		"expiresAt":     now.Add(24 * time.Hour),
	}
	res, err := db.Collection("users").InsertOne(ctx, doc)
	if err != nil {
		respondError(w, 500, "failed to create guest user")
		return
	}
	userID := res.InsertedID.(primitive.ObjectID).Hex()
	triggerWalletGeneration(userID)
	accessToken, refreshToken, err := issueTokenPair(ctx, userID, "guest")
	if err != nil {
		respondError(w, 500, "failed to issue tokens")
		return
	}

	doc["_id"] = res.InsertedID
	respondJSON(w, 201, map[string]interface{}{
		"accessToken":  accessToken,
		"refreshToken": refreshToken,
		"user":         sanitizeUser(doc),
	})
}

// ============================================================
// TOKEN MANAGEMENT
// ============================================================

func handleRefreshToken(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var body struct {
		RefreshToken string `json:"refreshToken"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		respondError(w, 400, "invalid request")
		return
	}

	session, err := getRefreshSession(ctx, body.RefreshToken)
	if err != nil {
		if errors.Is(err, errInvalidRefreshToken) {
			respondError(w, 401, "invalid or expired refresh token")
			return
		}
		respondError(w, 500, "refresh lookup failed")
		return
	}

	deleteRefreshToken(ctx, body.RefreshToken)
	newAccess, newRefresh, err := issueTokenPair(ctx, session.UserID, session.Role)
	if err != nil {
		respondError(w, 500, "failed to issue new tokens")
		return
	}

	respondJSON(w, 200, map[string]string{
		"accessToken":  newAccess,
		"refreshToken": newRefresh,
	})
}

func handleLogout(w http.ResponseWriter, r *http.Request) {
	var body struct {
		RefreshToken string `json:"refreshToken"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	if body.RefreshToken != "" {
		deleteRefreshToken(r.Context(), body.RefreshToken)
	}
	respondJSON(w, 200, map[string]string{"message": "logged out"})
}

func handleGetProfile(w http.ResponseWriter, r *http.Request) {
	claims, ok := authClaimsFromContext(r.Context())
	if !ok {
		respondError(w, 401, "unauthorized")
		return
	}
	oid, err := primitive.ObjectIDFromHex(claims.UserID)
	if err != nil {
		respondError(w, 400, "invalid user id")
		return
	}
	var user bson.M
	if err := db.Collection("users").FindOne(r.Context(), bson.M{"_id": oid}).Decode(&user); err != nil {
		respondError(w, 404, "user not found")
		return
	}
	respondJSON(w, 200, sanitizeUser(user))
}

func handleKYCInitiate(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	claims, ok := authClaimsFromContext(ctx)
	if !ok {
		respondError(w, 401, "unauthorized")
		return
	}

	var body struct {
		DocumentType   string `json:"documentType"`
		DocumentNumber string `json:"documentNumber"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.DocumentType == "" || body.DocumentNumber == "" {
		respondError(w, 400, "documentType and documentNumber are required")
		return
	}

	oid, err := primitive.ObjectIDFromHex(claims.UserID)
	if err != nil {
		respondError(w, 400, "invalid user id")
		return
	}

	request := bson.M{
		"userId":         claims.UserID,
		"documentType":   body.DocumentType,
		"documentNumber": body.DocumentNumber,
		"status":         "PENDING",
		"createdAt":      time.Now(),
		"updatedAt":      time.Now(),
	}
	if _, err := db.Collection("kyc_requests").InsertOne(ctx, request); err != nil {
		respondError(w, 500, "failed to start KYC review")
		return
	}
	_, _ = db.Collection("users").UpdateByID(ctx, oid, bson.M{"$set": bson.M{"kycStatus": "PENDING"}})

	respondJSON(w, 202, map[string]interface{}{
		"status":  "PENDING",
		"message": "KYC review initiated. You will be notified once verification is complete.",
	})
}

// ============================================================
// HELPERS
// ============================================================

func verifyFirebaseIDToken(ctx context.Context, idToken string) (*firebaseTokenClaims, error) {
	expectedIssuer := "https://securetoken.google.com/" + strings.TrimSpace(cfg.FirebaseProjectID)
	claims := &firebaseTokenClaims{}
	parsed, err := jwt.ParseWithClaims(
		idToken,
		claims,
		func(token *jwt.Token) (interface{}, error) {
			if token.Method.Alg() != jwt.SigningMethodRS256.Alg() {
				return nil, fmt.Errorf("firebase token uses unsupported alg %q", token.Method.Alg())
			}
			kid, _ := token.Header["kid"].(string)
			kid = strings.TrimSpace(kid)
			if kid == "" {
				return nil, errors.New("firebase token missing kid header")
			}
			key, err := getFirebasePublicKey(ctx, kid, false)
			if err == nil {
				return key, nil
			}
			return getFirebasePublicKey(ctx, kid, true)
		},
		jwt.WithValidMethods([]string{jwt.SigningMethodRS256.Alg()}),
		jwt.WithIssuer(expectedIssuer),
		jwt.WithAudience(strings.TrimSpace(cfg.FirebaseProjectID)),
	)
	if err != nil {
		return nil, err
	}
	if !parsed.Valid {
		return nil, errors.New("firebase token is invalid")
	}
	if strings.TrimSpace(claims.Subject) == "" {
		return nil, errors.New("firebase token subject is missing")
	}
	return claims, nil
}

func getFirebasePublicKey(ctx context.Context, kid string, forceRefresh bool) (*rsa.PublicKey, error) {
	keys, err := loadFirebasePublicKeys(ctx, forceRefresh)
	if err != nil {
		return nil, err
	}
	key, ok := keys[kid]
	if !ok || key == nil {
		return nil, fmt.Errorf("firebase public key for kid %q not found", kid)
	}
	return key, nil
}

func loadFirebasePublicKeys(ctx context.Context, forceRefresh bool) (map[string]*rsa.PublicKey, error) {
	now := time.Now()
	firebaseCertCache.mu.RLock()
	if !forceRefresh && len(firebaseCertCache.keys) > 0 && now.Before(firebaseCertCache.expiresAt) {
		keys := cloneFirebasePublicKeys(firebaseCertCache.keys)
		firebaseCertCache.mu.RUnlock()
		return keys, nil
	}
	firebaseCertCache.mu.RUnlock()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, firebasePublicKeysEndpoint, nil)
	if err != nil {
		return nil, err
	}
	resp, err := firebaseHTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return nil, fmt.Errorf(
			"firebase public key endpoint returned %d: %s",
			resp.StatusCode,
			strings.TrimSpace(string(body)),
		)
	}

	var certs map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&certs); err != nil {
		return nil, err
	}
	parsed := make(map[string]*rsa.PublicKey, len(certs))
	for kid, certPEM := range certs {
		publicKey, err := parseRSAPublicKeyFromCertificate(certPEM)
		if err != nil {
			log.Printf("firebase cert parse failed for kid %s: %v", kid, err)
			continue
		}
		parsed[kid] = publicKey
	}
	if len(parsed) == 0 {
		return nil, errors.New("firebase public keys payload contained no valid certificates")
	}

	ttl := parseMaxAge(resp.Header.Get("Cache-Control"), defaultFirebaseCertTTL)

	firebaseCertCache.mu.Lock()
	firebaseCertCache.keys = parsed
	firebaseCertCache.expiresAt = now.Add(ttl)
	keys := cloneFirebasePublicKeys(parsed)
	firebaseCertCache.mu.Unlock()

	return keys, nil
}

func cloneFirebasePublicKeys(src map[string]*rsa.PublicKey) map[string]*rsa.PublicKey {
	out := make(map[string]*rsa.PublicKey, len(src))
	for k, v := range src {
		out[k] = v
	}
	return out
}

func parseRSAPublicKeyFromCertificate(certPEM string) (*rsa.PublicKey, error) {
	block, _ := pem.Decode([]byte(certPEM))
	if block == nil {
		return nil, errors.New("could not decode PEM certificate")
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, err
	}
	key, ok := cert.PublicKey.(*rsa.PublicKey)
	if !ok {
		return nil, errors.New("certificate public key is not RSA")
	}
	return key, nil
}

func parseMaxAge(cacheControl string, fallback time.Duration) time.Duration {
	for _, token := range strings.Split(cacheControl, ",") {
		part := strings.TrimSpace(token)
		if !strings.HasPrefix(strings.ToLower(part), "max-age=") {
			continue
		}
		value := strings.TrimSpace(strings.TrimPrefix(strings.ToLower(part), "max-age="))
		seconds, err := strconv.Atoi(value)
		if err != nil || seconds <= 0 {
			break
		}
		return time.Duration(seconds) * time.Second
	}
	return fallback
}

func normalizeFirebaseProvider(provider string) string {
	switch strings.ToLower(strings.TrimSpace(provider)) {
	case "google.com":
		return "google"
	case "apple.com":
		return "apple"
	case "twitter.com":
		return "x"
	case "anonymous":
		return "guest"
	case "":
		return "firebase"
	default:
		normalized := strings.ToLower(strings.TrimSpace(provider))
		normalized = strings.TrimSuffix(normalized, ".com")
		normalized = strings.ReplaceAll(normalized, ".", "-")
		if normalized == "" {
			return "firebase"
		}
		return normalized
	}
}

func upsertUserByFirebase(ctx context.Context, identity firebaseIdentity) (bson.M, bool, string, error) {
	now := time.Now()
	existing, err := findUserForFirebase(ctx, identity.UID, identity.Email)
	if err != nil {
		return nil, false, "", err
	}
	guestExpiry := now.Add(24 * time.Hour)

	if existing == nil {
		doc := bson.M{
			"firebaseUid": identity.UID,
			"username": deriveUsername(
				identity.FullName,
				identity.Email,
				identity.ProviderName,
			),
			"isGuest":   identity.IsGuest,
			"kycStatus": "NONE",
			"tier":      "BRONZE",
			"createdAt": now,
			"updatedAt": now,
		}
		authProviders := []string{"firebase"}
		if identity.ProviderName != "" {
			authProviders = append(authProviders, identity.ProviderName)
		}
		doc["authProviders"] = authProviders
		if identity.Email != "" {
			doc["email"] = identity.Email
		}
		if identity.FullName != "" {
			doc["fullName"] = identity.FullName
		}
		if identity.AvatarURL != "" {
			doc["avatarUrl"] = identity.AvatarURL
		}
		if identity.IsGuest {
			doc["expiresAt"] = guestExpiry
		}
		res, err := db.Collection("users").InsertOne(ctx, doc)
		if err != nil {
			return nil, false, "", err
		}
		doc["_id"] = res.InsertedID
		role := "user"
		if identity.IsGuest {
			role = "guest"
		}
		return doc, true, role, nil
	}

	setFields := bson.M{
		"firebaseUid": identity.UID,
		"updatedAt":   now,
	}
	if identity.Email != "" {
		setFields["email"] = identity.Email
	}
	if identity.FullName != "" {
		setFields["fullName"] = identity.FullName
	}
	if identity.AvatarURL != "" {
		setFields["avatarUrl"] = identity.AvatarURL
	}
	username, _ := existing["username"].(string)
	if strings.TrimSpace(username) == "" {
		setFields["username"] = deriveUsername(
			identity.FullName,
			identity.Email,
			identity.ProviderName,
		)
	}

	update := bson.M{
		"$set":      setFields,
		"$addToSet": bson.M{"authProviders": bson.M{"$each": []string{"firebase", identity.ProviderName}}},
	}
	if identity.IsGuest {
		update["$set"].(bson.M)["isGuest"] = true
		update["$set"].(bson.M)["expiresAt"] = guestExpiry
	} else {
		update["$set"].(bson.M)["isGuest"] = false
		update["$unset"] = bson.M{"expiresAt": ""}
	}
	if identity.ProviderName == "" {
		update["$addToSet"] = bson.M{"authProviders": "firebase"}
	}

	_, err = db.Collection("users").UpdateOne(ctx, bson.M{"_id": existing["_id"]}, update)
	if err != nil {
		return nil, false, "", err
	}

	var updated bson.M
	if err := db.Collection("users").FindOne(ctx, bson.M{"_id": existing["_id"]}).Decode(&updated); err != nil {
		return nil, false, "", err
	}

	role := "user"
	if updatedGuest, ok := updated["isGuest"].(bool); ok && updatedGuest {
		role = "guest"
	}
	return updated, false, role, nil
}

func findUserForFirebase(ctx context.Context, firebaseUID, email string) (bson.M, error) {
	users := db.Collection("users")
	if firebaseUID != "" {
		var user bson.M
		err := users.FindOne(ctx, bson.M{"firebaseUid": firebaseUID}).Decode(&user)
		if err == nil {
			return user, nil
		}
		if err != mongo.ErrNoDocuments {
			return nil, err
		}
	}
	if email != "" {
		var user bson.M
		err := users.FindOne(ctx, bson.M{"email": email}).Decode(&user)
		if err == nil {
			return user, nil
		}
		if err != mongo.ErrNoDocuments {
			return nil, err
		}
	}
	return nil, nil
}

func verifyGoogleIDToken(ctx context.Context, idToken string) (*googleTokenInfo, error) {
	endpoint := "https://oauth2.googleapis.com/tokeninfo?id_token=" + url.QueryEscape(idToken)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	resp, err := googleHTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return nil, fmt.Errorf("google tokeninfo returned %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var claims googleTokenInfo
	if err := json.NewDecoder(resp.Body).Decode(&claims); err != nil {
		return nil, err
	}
	if strings.TrimSpace(claims.Subject) == "" {
		return nil, errors.New("google subject claim missing")
	}
	if !isAllowedGoogleAudience(claims.Audience, cfg.GoogleClientIDs) {
		return nil, errors.New("google audience mismatch")
	}
	if !isAllowedGoogleIssuer(claims.Issuer) {
		return nil, errors.New("google issuer mismatch")
	}
	if strings.TrimSpace(claims.Email) != "" && !googleBool(claims.EmailVerified) {
		return nil, errors.New("google email is not verified")
	}
	if claims.ExpiresAtUnix != "" {
		expiresAt, err := strconv.ParseInt(strings.TrimSpace(claims.ExpiresAtUnix), 10, 64)
		if err != nil {
			return nil, fmt.Errorf("google exp claim is invalid: %w", err)
		}
		if time.Now().Unix() >= expiresAt {
			return nil, errors.New("google token expired")
		}
	}

	claims.Email = strings.ToLower(strings.TrimSpace(claims.Email))
	claims.FullName = strings.TrimSpace(claims.FullName)
	claims.AvatarURL = strings.TrimSpace(claims.AvatarURL)
	claims.Subject = strings.TrimSpace(claims.Subject)
	return &claims, nil
}

func isAllowedGoogleAudience(audience string, allowed []string) bool {
	audience = strings.TrimSpace(audience)
	if audience == "" {
		return false
	}
	for _, candidate := range allowed {
		if strings.EqualFold(audience, strings.TrimSpace(candidate)) {
			return true
		}
	}
	return false
}

func isAllowedGoogleIssuer(issuer string) bool {
	issuer = strings.TrimSpace(issuer)
	return issuer == "" || issuer == "accounts.google.com" || issuer == "https://accounts.google.com"
}

func googleBool(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "true", "1", "yes":
		return true
	default:
		return false
	}
}

func upsertUserByGoogle(ctx context.Context, claims *googleTokenInfo) (bson.M, bool, error) {
	now := time.Now()
	existing, err := findUserForGoogle(ctx, claims.Subject, claims.Email)
	if err != nil {
		return nil, false, err
	}
	if existing == nil {
		doc := bson.M{
			"googleId":      claims.Subject,
			"username":      deriveUsername(claims.FullName, claims.Email, "google"),
			"authProviders": []string{"google"},
			"isGuest":       false,
			"kycStatus":     "NONE",
			"tier":          "BRONZE",
			"createdAt":     now,
			"updatedAt":     now,
		}
		if claims.FullName != "" {
			doc["fullName"] = claims.FullName
		}
		if claims.Email != "" {
			doc["email"] = claims.Email
		}
		if claims.AvatarURL != "" {
			doc["avatarUrl"] = claims.AvatarURL
		}
		res, err := db.Collection("users").InsertOne(ctx, doc)
		if err != nil {
			return nil, false, err
		}
		doc["_id"] = res.InsertedID
		return doc, true, nil
	}

	wasGuest, _ := existing["isGuest"].(bool)
	setFields := bson.M{
		"googleId":  claims.Subject,
		"isGuest":   false,
		"updatedAt": now,
	}
	if claims.Email != "" {
		setFields["email"] = claims.Email
	}
	if claims.FullName != "" {
		setFields["fullName"] = claims.FullName
	}
	if claims.AvatarURL != "" {
		setFields["avatarUrl"] = claims.AvatarURL
	}
	username, _ := existing["username"].(string)
	if strings.TrimSpace(username) == "" {
		setFields["username"] = deriveUsername(claims.FullName, claims.Email, "google")
	}

	_, err = db.Collection("users").UpdateOne(ctx, bson.M{"_id": existing["_id"]}, bson.M{
		"$set":      setFields,
		"$addToSet": bson.M{"authProviders": "google"},
		"$unset":    bson.M{"expiresAt": ""},
	})
	if err != nil {
		return nil, false, err
	}

	var updated bson.M
	if err := db.Collection("users").FindOne(ctx, bson.M{"_id": existing["_id"]}).Decode(&updated); err != nil {
		return nil, false, err
	}
	return updated, wasGuest, nil
}

func findUserForGoogle(ctx context.Context, googleID, email string) (bson.M, error) {
	users := db.Collection("users")
	if googleID != "" {
		var user bson.M
		err := users.FindOne(ctx, bson.M{"googleId": googleID}).Decode(&user)
		if err == nil {
			return user, nil
		}
		if err != mongo.ErrNoDocuments {
			return nil, err
		}
	}
	if email != "" {
		var user bson.M
		err := users.FindOne(ctx, bson.M{"email": email}).Decode(&user)
		if err == nil {
			return user, nil
		}
		if err != mongo.ErrNoDocuments {
			return nil, err
		}
	}
	return nil, nil
}

func setupIndexes() {
	ctx := context.Background()
	db.Collection("users").Indexes().CreateMany(ctx, []mongo.IndexModel{
		{Keys: bson.D{{Key: "phone", Value: 1}}, Options: options.Index().SetUnique(true).SetSparse(true)},
		{Keys: bson.D{{Key: "email", Value: 1}}, Options: options.Index().SetUnique(true).SetSparse(true)},
		{Keys: bson.D{{Key: "firebaseUid", Value: 1}}, Options: options.Index().SetUnique(true).SetSparse(true)},
		{Keys: bson.D{{Key: "googleId", Value: 1}}, Options: options.Index().SetUnique(true).SetSparse(true)},
		{Keys: bson.D{{Key: "facebookId", Value: 1}}, Options: options.Index().SetUnique(true).SetSparse(true)},
		{Keys: bson.D{{Key: "appleId", Value: 1}}, Options: options.Index().SetUnique(true).SetSparse(true)},
	})
	db.Collection("otps").Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys:    bson.D{{Key: "expiresAt", Value: 1}},
		Options: options.Index().SetExpireAfterSeconds(0),
	})
	db.Collection("kyc_requests").Indexes().CreateMany(ctx, []mongo.IndexModel{
		{Keys: bson.D{{Key: "userId", Value: 1}, {Key: "createdAt", Value: -1}}},
		{Keys: bson.D{{Key: "status", Value: 1}}},
	})
	db.Collection("password_resets").Indexes().CreateMany(ctx, []mongo.IndexModel{
		{Keys: bson.D{{Key: "tokenHash", Value: 1}}, Options: options.Index().SetUnique(true)},
		{Keys: bson.D{{Key: "expiresAt", Value: 1}}, Options: options.Index().SetExpireAfterSeconds(0)},
	})
	log.Println("MongoDB indexes ensured")
}

func issueTokenPair(ctx context.Context, userID, role string) (string, string, error) {
	if jwtManager == nil {
		return "", "", errors.New("token manager not initialised")
	}
	access, err := jwtManager.IssueAccessToken(userID, role)
	if err != nil {
		return "", "", err
	}
	refresh, err := generateSecureToken(32)
	if err != nil {
		return "", "", err
	}
	if err := storeRefreshToken(ctx, userID, role, refresh); err != nil {
		return "", "", err
	}
	return access, refresh, nil
}

var errInvalidRefreshToken = errors.New("invalid refresh token")

func storeRefreshToken(ctx context.Context, userID, role, token string) error {
	if rdb == nil {
		return errors.New("redis client not initialised")
	}
	if token == "" {
		return errors.New("refresh token empty")
	}
	session := refreshSession{UserID: userID, Role: role}
	payload, err := json.Marshal(session)
	if err != nil {
		return err
	}
	key := refreshKey(hashToken(token))
	return rdb.Set(ctx, key, payload, cfg.RefreshTTL).Err()
}

func getRefreshSession(ctx context.Context, token string) (*refreshSession, error) {
	if rdb == nil {
		return nil, errors.New("redis client not initialised")
	}
	if token == "" {
		return nil, errInvalidRefreshToken
	}
	key := refreshKey(hashToken(token))
	raw, err := rdb.Get(ctx, key).Result()
	if err != nil {
		if errors.Is(err, redis.Nil) {
			return nil, errInvalidRefreshToken
		}
		return nil, err
	}
	var session refreshSession
	if err := json.Unmarshal([]byte(raw), &session); err != nil {
		return nil, errInvalidRefreshToken
	}
	if session.UserID == "" {
		return nil, errInvalidRefreshToken
	}
	return &session, nil
}

func deleteRefreshToken(ctx context.Context, token string) {
	if rdb == nil || token == "" {
		return
	}
	_, _ = rdb.Del(ctx, refreshKey(hashToken(token))).Result()
}

func refreshKey(hash string) string {
	return "refresh:" + hash
}

func hashToken(token string) string {
	h := sha256.Sum256([]byte(token))
	return hex.EncodeToString(h[:])
}

func generateSecureToken(n int) (string, error) {
	if n <= 0 {
		n = 32
	}
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func generateOTP(length int) string {
	const digits = "0123456789"
	otp := make([]byte, length)
	for i := range otp {
		n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(digits))))
		otp[i] = digits[n.Int64()]
	}
	return string(otp)
}

func hashOTP(code string) string {
	h := sha256.Sum256([]byte(code))
	return hex.EncodeToString(h[:])
}

func hashPassword(password string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	hash := argon2.IDKey([]byte(password), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
	return hex.EncodeToString(salt) + ":" + hex.EncodeToString(hash), nil
}

func verifyPassword(password, stored string) bool {
	parts := strings.Split(stored, ":")
	if len(parts) != 2 {
		return false
	}
	salt, err := hex.DecodeString(parts[0])
	if err != nil {
		return false
	}
	expected, err := hex.DecodeString(parts[1])
	if err != nil {
		return false
	}
	hash := argon2.IDKey([]byte(password), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
	return subtle.ConstantTimeCompare(hash, expected) == 1
}

func upsertUserByPhone(ctx context.Context, phone string) (bson.M, error) {
	now := time.Now()
	res := db.Collection("users").FindOneAndUpdate(
		ctx,
		bson.M{"phone": phone},
		bson.M{
			"$setOnInsert": bson.M{
				"phone":         phone,
				"authProviders": []string{"phone"},
				"isGuest":       false,
				"kycStatus":     "NONE",
				"tier":          "BRONZE",
				"createdAt":     now,
			},
			"$set": bson.M{"updatedAt": now},
		},
		options.FindOneAndUpdate().SetUpsert(true).SetReturnDocument(options.After),
	)
	var user bson.M
	if err := res.Decode(&user); err != nil {
		return nil, err
	}
	return user, nil
}

func sanitizeUser(user bson.M) map[string]interface{} {
	out := map[string]interface{}{}
	if id, err := extractUserID(user); err == nil {
		out["id"] = id
	}
	for _, k := range []string{"username", "fullName", "email", "phone", "avatarUrl", "tier", "kycStatus", "isGuest", "authProviders"} {
		if v, ok := user[k]; ok {
			out[k] = v
		}
	}
	if created, ok := user["createdAt"]; ok {
		out["createdAt"] = created
	}
	if updated, ok := user["updatedAt"]; ok {
		out["updatedAt"] = updated
	}
	return out
}

func extractUserID(user bson.M) (string, error) {
	if user == nil {
		return "", errors.New("user document nil")
	}
	switch v := user["_id"].(type) {
	case primitive.ObjectID:
		return v.Hex(), nil
	case string:
		if v == "" {
			return "", errors.New("user id empty")
		}
		return v, nil
	default:
		return "", errors.New("user id missing")
	}
}

func deriveUsername(fullName, email, provider string) string {
	if slug := slugifyUsername(fullName); slug != "" {
		return slug
	}
	if email != "" {
		if idx := strings.Index(email, "@"); idx > 0 {
			if slug := slugifyUsername(email[:idx]); slug != "" {
				return slug
			}
		}
	}
	base := provider
	if base == "" {
		base = "user"
	}
	slugBase := slugifyUsername(base)
	if slugBase == "" {
		slugBase = "user"
	}
	suffix, err := generateSecureToken(4)
	if err != nil || len(suffix) < 6 {
		suffix = "gh" + time.Now().Format("150405")
	}
	if len(suffix) > 6 {
		suffix = suffix[:6]
	}
	return slugBase + "-" + strings.ToLower(suffix)
}

func slugifyUsername(raw string) string {
	raw = strings.ToLower(strings.TrimSpace(raw))
	if raw == "" {
		return ""
	}
	slug := usernameSanitizer.ReplaceAllString(raw, "-")
	slug = strings.Trim(slug, "-")
	if slug == "" {
		return ""
	}
	if len(slug) > 32 {
		slug = slug[:32]
	}
	return slug
}

func storePasswordResetToken(ctx context.Context, userID, email, token string) error {
	if db == nil {
		return errors.New("db not initialised")
	}
	hash := hashToken(token)
	expiry := time.Now().Add(cfg.PasswordResetTTL)
	doc := bson.M{
		"userId":    userID,
		"email":     email,
		"tokenHash": hash,
		"used":      false,
		"expiresAt": expiry,
		"createdAt": time.Now(),
	}
	_, err := db.Collection("password_resets").InsertOne(ctx, doc)
	return err
}

func consumePasswordResetToken(ctx context.Context, token string) (bson.M, error) {
	if db == nil {
		return nil, errors.New("db not initialised")
	}
	hash := hashToken(token)
	now := time.Now()
	res := db.Collection("password_resets").FindOneAndUpdate(
		ctx,
		bson.M{
			"tokenHash": hash,
			"used":      false,
			"expiresAt": bson.M{"$gt": now},
		},
		bson.M{"$set": bson.M{"used": true, "usedAt": now}},
		options.FindOneAndUpdate().SetReturnDocument(options.After),
	)
	var doc bson.M
	if err := res.Decode(&doc); err != nil {
		return nil, errors.New("invalid or expired reset token")
	}
	return doc, nil
}

// ============================================================
// MIDDLEWARE
// ============================================================

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestOrigin := strings.TrimSpace(r.Header.Get("Origin"))
		allowOrigin, allowed := resolveAllowedOrigin(requestOrigin)
		if requestOrigin != "" && !allowed {
			respondError(w, http.StatusForbidden, "origin not allowed")
			return
		}
		if allowOrigin != "" {
			w.Header().Set("Access-Control-Allow-Origin", allowOrigin)
			if allowOrigin != "*" {
				appendVaryHeader(w, "Origin")
			}
		}
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Internal-Key")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
			respondError(w, 401, "authorization required")
			return
		}
		if jwtManager == nil {
			respondError(w, 500, "token manager unavailable")
			return
		}
		tokenStr := strings.TrimSpace(strings.TrimPrefix(authHeader, "Bearer "))
		claims, err := jwtManager.Parse(tokenStr)
		if err != nil {
			respondError(w, 401, "invalid or expired token")
			return
		}
		ctx := context.WithValue(r.Context(), ctxUserKey, claims)
		next(w, r.WithContext(ctx))
	}
}

func respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}

func respondError(w http.ResponseWriter, status int, message string) {
	respondJSON(w, status, map[string]string{"error": message})
}

func authClaimsFromContext(ctx context.Context) (*token.Claims, bool) {
	if ctx == nil {
		return nil, false
	}
	claims, ok := ctx.Value(ctxUserKey).(*token.Claims)
	return claims, ok
}

func configureAllowedOrigins(raw string) {
	allowedOriginSet = make(map[string]struct{})
	allowAllOrigins = false

	for _, part := range strings.Split(raw, ",") {
		value := strings.TrimSpace(part)
		if value == "" {
			continue
		}
		if value == "*" {
			allowAllOrigins = true
			continue
		}
		normalized := normalizeOrigin(value)
		if normalized == "" {
			continue
		}
		allowedOriginSet[normalized] = struct{}{}
	}

	if allowAllOrigins {
		log.Printf("CORS: allowing all origins")
		return
	}
	if len(allowedOriginSet) == 0 {
		log.Printf("CORS: no allowed origins configured; defaulting to deny when Origin is present")
		return
	}
	log.Printf("CORS: allowing %d origin(s)", len(allowedOriginSet))
}

func resolveAllowedOrigin(origin string) (string, bool) {
	if allowAllOrigins {
		return "*", true
	}
	if origin == "" {
		return "", true
	}
	normalized := normalizeOrigin(origin)
	if normalized == "" {
		return "", false
	}
	_, ok := allowedOriginSet[normalized]
	if !ok {
		return "", false
	}
	// Echo request origin for explicit allow-list mode.
	return origin, true
}

func normalizeOrigin(origin string) string {
	origin = strings.TrimSpace(origin)
	origin = strings.TrimRight(origin, "/")
	if origin == "" {
		return ""
	}
	parsed, err := url.Parse(origin)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return strings.ToLower(origin)
	}
	return strings.ToLower(parsed.Scheme) + "://" + strings.ToLower(parsed.Host)
}

func appendVaryHeader(w http.ResponseWriter, value string) {
	existing := w.Header().Get("Vary")
	if existing == "" {
		w.Header().Set("Vary", value)
		return
	}
	for _, part := range strings.Split(existing, ",") {
		if strings.EqualFold(strings.TrimSpace(part), value) {
			return
		}
	}
	w.Header().Set("Vary", existing+", "+value)
}

func registerRoute(mux *http.ServeMux, method, pattern string, handler http.HandlerFunc) {
	mux.HandleFunc(pattern, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != method {
			w.Header().Set("Allow", method)
			respondError(w, http.StatusMethodNotAllowed, "method not allowed")
			return
		}
		handler(w, r)
	})
}

type loggingResponseWriter struct {
	http.ResponseWriter
	status int
	length int
}

func (lrw *loggingResponseWriter) WriteHeader(statusCode int) {
	lrw.status = statusCode
	lrw.ResponseWriter.WriteHeader(statusCode)
}

func (lrw *loggingResponseWriter) Write(b []byte) (int, error) {
	if lrw.status == 0 {
		lrw.status = http.StatusOK
	}
	n, err := lrw.ResponseWriter.Write(b)
	lrw.length += n
	return n, err
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		lrw := &loggingResponseWriter{ResponseWriter: w}
		next.ServeHTTP(lrw, r)
		duration := time.Since(start)
		log.Printf("%s %s -> %d (%s)", r.Method, r.URL.Path, lrw.status, duration)
	})
}

// -----------------------------------------------------------------------------
// JIT Wallet Generation
// -----------------------------------------------------------------------------
func triggerWalletGeneration(userID string) {
	if cfg == nil || cfg.PaymentGatewayURL == "" || cfg.InternalServiceKey == "" {
		log.Printf("[auth][generate-all] missing config for JIT wallet internal call")
		return
	}

	go func() {
		// allow brief delay to ensure user doc replication in mongo (if using replica sets)
		time.Sleep(1 * time.Second)

		payload := map[string]string{"userId": userID}
		body, _ := json.Marshal(payload)

		url := fmt.Sprintf("%s/internal/crypto/wallets/generate-all", strings.TrimRight(cfg.PaymentGatewayURL, "/"))

		req, err := http.NewRequest("POST", url, bytes.NewBuffer(body))
		if err != nil {
			log.Printf("[auth][generate-all] failed to create request for %s: %v", userID, err)
			return
		}

		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Internal-Key", cfg.InternalServiceKey)

		client := &http.Client{Timeout: 30 * time.Second} // Tatum API calls might take 10-15s for 3 coins
		resp, err := client.Do(req)
		if err != nil {
			log.Printf("[auth][generate-all] network error requesting wallets for %s: %v", userID, err)
			return
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			log.Printf("[auth][generate-all] payment-gateway returned %d for user %s", resp.StatusCode, userID)
			return
		}

		log.Printf("[auth][generate-all] successfully triggered 3 wallets for new user %s", userID)
	}()
}
