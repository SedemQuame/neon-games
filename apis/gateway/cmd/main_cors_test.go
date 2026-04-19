package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestCORSMiddleware_Preflight_AllowsConfiguredOrigin(t *testing.T) {
	policy := parseCORSPolicy("https://app.example.com")
	called := false
	handler := corsMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusOK)
	}), policy)

	req := httptest.NewRequest(http.MethodOptions, "/api/v1/wallet/balance", nil)
	req.Header.Set("Origin", "https://app.example.com")
	req.Header.Set("Access-Control-Request-Method", "GET")
	req.Header.Set("Access-Control-Request-Headers", "authorization,content-type")
	rr := httptest.NewRecorder()

	handler.ServeHTTP(rr, req)

	if called {
		t.Fatalf("preflight should not call downstream handler")
	}
	if rr.Code != http.StatusNoContent {
		t.Fatalf("expected 204 for preflight, got %d", rr.Code)
	}
	if got := rr.Header().Get("Access-Control-Allow-Origin"); got != "https://app.example.com" {
		t.Fatalf("expected Access-Control-Allow-Origin to echo origin, got %q", got)
	}
}

func TestCORSMiddleware_Preflight_BlocksDisallowedOrigin(t *testing.T) {
	policy := parseCORSPolicy("https://app.example.com")
	handler := corsMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}), policy)

	req := httptest.NewRequest(http.MethodOptions, "/api/v1/wallet/balance", nil)
	req.Header.Set("Origin", "https://evil.example.com")
	req.Header.Set("Access-Control-Request-Method", "GET")
	rr := httptest.NewRecorder()

	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for disallowed origin, got %d", rr.Code)
	}
}

func TestCORSMiddleware_AllowAll_SetsWildcardHeader(t *testing.T) {
	policy := parseCORSPolicy("*")
	handler := corsMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}), policy)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/wallet/balance", nil)
	req.Header.Set("Origin", "https://carefree-perfection-production-9fb0.up.railway.app")
	rr := httptest.NewRecorder()

	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}
	if got := rr.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Fatalf("expected wildcard Access-Control-Allow-Origin, got %q", got)
	}
}

func TestCORSMiddleware_AuthPath_BypassesGatewayCORS(t *testing.T) {
	policy := parseCORSPolicy("*")
	called := false
	handler := corsMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusCreated)
	}), policy)

	req := httptest.NewRequest(http.MethodOptions, "/api/v1/auth/firebase/login", nil)
	req.Header.Set("Origin", "https://carefree-perfection-production-9fb0.up.railway.app")
	req.Header.Set("Access-Control-Request-Method", "POST")
	rr := httptest.NewRecorder()

	handler.ServeHTTP(rr, req)

	if !called {
		t.Fatalf("expected auth path to bypass gateway cors and reach downstream handler")
	}
	if rr.Code != http.StatusCreated {
		t.Fatalf("expected downstream status to be preserved, got %d", rr.Code)
	}
	if got := rr.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("expected gateway to not set CORS headers for auth path, got %q", got)
	}
}
