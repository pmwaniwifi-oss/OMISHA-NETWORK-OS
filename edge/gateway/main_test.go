package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestReadiness(t *testing.T) {
	for _, tc := range []struct {
		name   string
		err    error
		status int
	}{
		{"healthy cache", nil, http.StatusOK},
		{"unavailable cache", errors.New("unavailable"), http.StatusServiceUnavailable},
	} {
		t.Run(tc.name, func(t *testing.T) {
			h := handlerWithPing(func(context.Context) error { return tc.err })
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, httptest.NewRequest("GET", "/readyz", nil))
			if rec.Code != tc.status {
				t.Fatalf("got %d, want %d", rec.Code, tc.status)
			}
		})
	}
}

func TestHealthAndUnimplementedCustomerAPI(t *testing.T) {
	h := handlerWithPing(func(context.Context) error { return nil })
	for _, tc := range []struct {
		path   string
		status int
	}{
		{"/healthz", http.StatusOK}, {"/v1/customer", http.StatusNotImplemented},
	} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest("GET", tc.path, nil))
		if rec.Code != tc.status {
			t.Errorf("%s: got %d, want %d", tc.path, rec.Code, tc.status)
		}
	}
}

