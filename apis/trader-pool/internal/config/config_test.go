package config

import "testing"

func TestResolveRedisFromHostPortVars(t *testing.T) {
	t.Setenv("REDIS_ADDR", "")
	t.Setenv("REDISHOST", "redis.railway.internal")
	t.Setenv("REDISPORT", "6379")
	t.Setenv("REDIS_PASSWORD", "")
	t.Setenv("REDISPASSWORD", "railway-secret")
	t.Setenv("REDIS_URL", "")

	if got := resolveRedisAddr(); got != "redis.railway.internal:6379" {
		t.Fatalf("resolveRedisAddr() = %q, want %q", got, "redis.railway.internal:6379")
	}
	if got := resolveRedisPassword(); got != "railway-secret" {
		t.Fatalf("resolveRedisPassword() = %q, want %q", got, "railway-secret")
	}
}

func TestResolveRedisFromURL(t *testing.T) {
	t.Setenv("REDIS_ADDR", "localhost:6379")
	t.Setenv("REDISHOST", "")
	t.Setenv("REDISPORT", "")
	t.Setenv("REDIS_PASSWORD", "local-secret")
	t.Setenv("REDISPASSWORD", "")
	t.Setenv("REDIS_URL", "redis://default:railway-secret@redis.railway.internal:6379")

	if got := resolveRedisAddr(); got != "redis.railway.internal:6379" {
		t.Fatalf("resolveRedisAddr() = %q, want %q", got, "redis.railway.internal:6379")
	}
	if got := resolveRedisPassword(); got != "railway-secret" {
		t.Fatalf("resolveRedisPassword() = %q, want %q", got, "railway-secret")
	}
}

func TestResolveRedisFromBareHostURLValue(t *testing.T) {
	t.Setenv("REDIS_ADDR", "localhost:6379")
	t.Setenv("REDISHOST", "")
	t.Setenv("REDISPORT", "")
	t.Setenv("REDIS_PASSWORD", "shared-secret")
	t.Setenv("REDISPASSWORD", "")
	t.Setenv("REDIS_URL", "redis.railway.internal")

	if got := resolveRedisAddr(); got != "redis.railway.internal:6379" {
		t.Fatalf("resolveRedisAddr() = %q, want %q", got, "redis.railway.internal:6379")
	}
	if got := resolveRedisPassword(); got != "shared-secret" {
		t.Fatalf("resolveRedisPassword() = %q, want %q", got, "shared-secret")
	}
}
