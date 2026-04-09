package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
)

type upstream struct {
	name   string
	target string
	proxy  *httputil.ReverseProxy
}

type route struct {
	prefix   string
	upstream *upstream
}

func main() {
	log.SetOutput(os.Stdout)

	gatewayPort := env("GATEWAY_PORT", "80")

	upstreams := []*upstream{
		newUpstream("auth-service", "http://127.0.0.1:"+env("AUTH_SERVICE_PORT", "8001")),
		newUpstream("game-session-service", "http://127.0.0.1:"+env("GAME_SESSION_PORT", "8002")),
		newUpstream("payment-gateway", "http://127.0.0.1:"+env("PAYMENT_GATEWAY_PORT", "8003")),
		newUpstream("wallet-service", "http://127.0.0.1:"+env("WALLET_SERVICE_PORT", "8004")),
	}

	routeTable := []route{
		{prefix: "/api/v1/auth/", upstream: upstreams[0]},
		{prefix: "/api/v1/games/", upstream: upstreams[1]},
		{prefix: "/ws/payments", upstream: upstreams[2]},
		{prefix: "/api/v1/payments/", upstream: upstreams[2]},
		{prefix: "/webhooks/payment/", upstream: upstreams[2]},
		{prefix: "/api/v1/wallet/", upstream: upstreams[3]},
		{prefix: "/api/v1/leaderboard/", upstream: upstreams[3]},
		{prefix: "/ws", upstream: upstreams[1]},
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/health" {
			http.NotFound(w, r)
			return
		}

		writeJSON(w, http.StatusOK, map[string]string{
			"status":  "ok",
			"service": "gateway",
		})
	})

	mux.HandleFunc("/health/upstreams", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/health/upstreams" {
			http.NotFound(w, r)
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()

		payload := map[string]any{
			"status":   "ok",
			"service":  "gateway",
			"services": map[string]any{},
		}
		services := payload["services"].(map[string]any)
		statusCode := http.StatusOK

		for _, upstream := range upstreams {
			serviceStatus := map[string]any{
				"target": upstream.target,
				"status": "unhealthy",
			}
			req, err := http.NewRequestWithContext(ctx, http.MethodGet, upstream.target+"/health", nil)
			if err == nil {
				resp, reqErr := http.DefaultClient.Do(req)
				if reqErr == nil {
					serviceStatus["http_status"] = resp.StatusCode
					if resp.StatusCode >= 200 && resp.StatusCode < 300 {
						serviceStatus["status"] = "ok"
					} else {
						statusCode = http.StatusServiceUnavailable
						payload["status"] = "degraded"
					}
					_ = resp.Body.Close()
				} else {
					serviceStatus["error"] = reqErr.Error()
					statusCode = http.StatusServiceUnavailable
					payload["status"] = "degraded"
				}
			} else {
				serviceStatus["error"] = err.Error()
				statusCode = http.StatusServiceUnavailable
				payload["status"] = "degraded"
			}

			services[upstream.name] = serviceStatus
		}

		writeJSON(w, statusCode, payload)
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		addSecurityHeaders(w)

		for _, route := range routeTable {
			if strings.HasPrefix(r.URL.Path, route.prefix) {
				route.upstream.proxy.ServeHTTP(w, r)
				return
			}
		}

		writeJSON(w, http.StatusNotFound, map[string]string{
			"error": "route not found",
		})
	})

	server := &http.Server{
		Addr:              ":" + gatewayPort,
		Handler:           loggingMiddleware(mux),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("Gateway listening on :%s", gatewayPort)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("gateway error: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = server.Shutdown(ctx)
}

func newUpstream(name, rawTarget string) *upstream {
	target, err := url.Parse(rawTarget)
	if err != nil {
		log.Fatalf("invalid upstream target for %s: %v", name, err)
	}

	proxy := httputil.NewSingleHostReverseProxy(target)
	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalHost := req.Host
		originalDirector(req)
		req.Host = target.Host
		if originalHost != "" {
			req.Header.Set("X-Forwarded-Host", originalHost)
		}
		if req.Header.Get("X-Forwarded-Proto") == "" {
			req.Header.Set("X-Forwarded-Proto", "http")
		}
	}
	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		writeJSON(w, http.StatusBadGateway, map[string]string{
			"error": err.Error(),
		})
	}
	proxy.FlushInterval = -1

	return &upstream{
		name:   name,
		target: strings.TrimRight(rawTarget, "/"),
		proxy:  proxy,
	}
}

func addSecurityHeaders(w http.ResponseWriter) {
	w.Header().Set("X-Frame-Options", "DENY")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("X-XSS-Protection", "1; mode=block")
	w.Header().Set("Content-Security-Policy", "default-src 'self'")
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s (%s)", r.Method, r.URL.Path, time.Since(start))
	})
}

func env(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}
