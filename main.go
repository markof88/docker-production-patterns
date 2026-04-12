package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// healthResponse is returned by /healthz and /readyz.
type healthResponse struct {
	Status  string `json:"status"`
	Env     string `json:"env"`
	Version string `json:"version"`
}

// rootResponse is returned by /.
type rootResponse struct {
	Message   string    `json:"message"`
	Timestamp time.Time `json:"timestamp"`
}

var (
	// appVersion is set at build time via -ldflags.
	appVersion = "dev"
)

func main() {
	// Support a -healthcheck flag so the Docker HEALTHCHECK instruction can
	// call the binary itself instead of needing curl or wget (which don't
	// exist in a distroless image).
	if len(os.Args) > 1 && os.Args[1] == "-healthcheck" {
		resp, err := http.Get("http://localhost:" + getEnv("PORT", "8080") + "/healthz")
		if err != nil || resp.StatusCode != http.StatusOK {
			fmt.Fprintln(os.Stderr, "healthcheck failed")
			os.Exit(1)
		}
		os.Exit(0)
	}

	// Structured logging — JSON in production, text locally via LOG_LEVEL=debug.
	logLevel := slog.LevelInfo
	if os.Getenv("LOG_LEVEL") == "debug" {
		logLevel = slog.LevelDebug
	}
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: logLevel,
	}))
	slog.SetDefault(logger)

	port := getEnv("PORT", "8080")
	appEnv := getEnv("APP_ENV", "production")

	mux := http.NewServeMux()

	// Liveness probe — "am I alive?" The process is running, so yes.
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, healthResponse{
			Status:  "ok",
			Env:     appEnv,
			Version: appVersion,
		})
	})

	// Readiness probe — "am I ready to serve traffic?"
	// In a real app this would check DB connections, downstream deps, etc.
	// This app has no dependencies so ready == alive.
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, healthResponse{
			Status:  "ready",
			Env:     appEnv,
			Version: appVersion,
		})
	})

	// Application endpoint.
	mux.HandleFunc("GET /", func(w http.ResponseWriter, r *http.Request) {
		slog.Info("request received", "path", r.URL.Path, "method", r.Method)
		writeJSON(w, http.StatusOK, rootResponse{
			Message:   "Hello from a production-grade container",
			Timestamp: time.Now().UTC(),
		})
	})

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	// Start server in a goroutine so we can listen for shutdown signals.
	serverErr := make(chan error, 1)
	go func() {
		slog.Info("server starting", "port", port, "env", appEnv, "version", appVersion)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			serverErr <- err
		}
	}()

	// Graceful shutdown — wait for SIGTERM (Kubernetes) or SIGINT (Ctrl+C).
	// Kubernetes sends SIGTERM when terminating a pod. We have up to
	// terminationGracePeriodSeconds (default 30s) to finish in-flight requests
	// before the kubelet sends SIGKILL.
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)

	select {
	case err := <-serverErr:
		slog.Error("server failed", "error", err)
		os.Exit(1)
	case sig := <-quit:
		slog.Info("shutdown signal received", "signal", sig)
	}

	// Allow up to 5 seconds for in-flight requests to complete.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		slog.Error("server shutdown failed", "error", err)
		os.Exit(1)
	}

	slog.Info("server stopped gracefully")
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("failed to encode response", "error", err)
	}
}
