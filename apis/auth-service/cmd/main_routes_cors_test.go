package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"gamehub/auth-service/internal/config"
)

func TestRegisterRoutes_FirebaseLoginRouteExists(t *testing.T) {
	originalCfg := cfg
	defer func() { cfg = originalCfg }()

	cfg = &config.Config{
		FirebaseProjectID: "test-project",
		AllowedOrigins:    "*",
	}
	configureAllowedOrigins(cfg.AllowedOrigins)

	mux := http.NewServeMux()
	registerRoutes(mux)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/firebase/login", strings.NewReader(`{}`))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()

	mux.ServeHTTP(rr, req)

	if rr.Code == http.StatusNotFound || rr.Code == http.StatusMethodNotAllowed {
		t.Fatalf("firebase route not registered correctly, got status %d", rr.Code)
	}
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected firebase login to reject empty idToken with 400, got %d body=%s", rr.Code, rr.Body.String())
	}
}

func TestCorsMiddleware_AllowsConfiguredOrigins(t *testing.T) {
	originalCfg := cfg
	defer func() { cfg = originalCfg }()

	cfg = &config.Config{
		AllowedOrigins: "https://app.example.com, https://carefree-perfection-production-9fb0.up.railway.app",
	}
	configureAllowedOrigins(cfg.AllowedOrigins)

	handler := corsMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodOptions, "/api/v1/auth/firebase/login", nil)
	req.Header.Set("Origin", "https://carefree-perfection-production-9fb0.up.railway.app")
	rr := httptest.NewRecorder()

	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusNoContent {
		t.Fatalf("expected preflight 204 for allowed origin, got %d", rr.Code)
	}
	if got := rr.Header().Get("Access-Control-Allow-Origin"); got != "https://carefree-perfection-production-9fb0.up.railway.app" {
		t.Fatalf("expected echoed allow-origin header, got %q", got)
	}
}

func TestCorsMiddleware_BlocksDisallowedOrigins(t *testing.T) {
	originalCfg := cfg
	defer func() { cfg = originalCfg }()

	cfg = &config.Config{
		AllowedOrigins: "https://gamehub.io",
	}
	configureAllowedOrigins(cfg.AllowedOrigins)

	handler := corsMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/firebase/login", strings.NewReader(`{}`))
	req.Header.Set("Origin", "https://carefree-perfection-production-9fb0.up.railway.app")
	rr := httptest.NewRecorder()

	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for disallowed origin, got %d", rr.Code)
	}
}
