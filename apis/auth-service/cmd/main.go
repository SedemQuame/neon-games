package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log"
	"math/big"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

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
)

const (
	otpLength           = 6
	argonTime    uint32 = 1
	argonMemory  uint32 = 64 * 1024
	argonThreads uint8  = 4
	argonKeyLen  uint32 = 32
)

type ctxKey string

const ctxUserKey ctxKey = "auth_user"

type refreshSession struct {
	UserID string `json:"userId"`
	Role   string `json:"role"`
}

func main() {
	cfg = config.Load()
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

func setupIndexes() {
	ctx := context.Background()
	db.Collection("users").Indexes().CreateMany(ctx, []mongo.IndexModel{
		{Keys: bson.D{{Key: "phone", Value: 1}}, Options: options.Index().SetUnique(true).SetSparse(true)},
		{Keys: bson.D{{Key: "email", Value: 1}}, Options: options.Index().SetUnique(true).SetSparse(true)},
		{Keys: bson.D{{Key: "googleId", Value: 1}}, Options: options.Index().SetUnique(true).SetSparse(true)},
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
	for _, k := range []string{"username", "email", "phone", "tier", "kycStatus", "isGuest", "authProviders"} {
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
		w.Header().Set("Access-Control-Allow-Origin", cfg.AllowedOrigins)
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
