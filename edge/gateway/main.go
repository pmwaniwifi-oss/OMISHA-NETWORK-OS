package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"time"
)

func valkeyPing(ctx context.Context, address string) error {
	conn, err := (&net.Dialer{Timeout: 2 * time.Second}).DialContext(ctx, "tcp", address)
	if err != nil {
		return err
	}
	defer conn.Close()
	if err := conn.SetDeadline(time.Now().Add(2 * time.Second)); err != nil {
		return err
	}
	if _, err = conn.Write([]byte("*1\r\n$4\r\nPING\r\n")); err != nil {
		return err
	}
	line, err := bufio.NewReaderSize(conn, 128).ReadString('\n')
	if err != nil {
		return err
	}
	if line != "+PONG\r\n" {
		return errors.New("unexpected Valkey response")
	}
	return nil
}

func handler(address string) http.Handler {
	return handlerWithPing(func(ctx context.Context) error { return valkeyPing(ctx, address) })
}

func handlerWithPing(ping func(context.Context) error) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, "{\"status\":\"alive\"}\n")
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if err := ping(r.Context()); err != nil {
			log.Printf("Valkey readiness failed: %v", err)
			w.WriteHeader(http.StatusServiceUnavailable)
			fmt.Fprint(w, "{\"status\":\"unavailable\"}\n")
			return
		}
		fmt.Fprint(w, "{\"status\":\"ready\"}\n")
	})
	googleIdentity := newGoogleIdentityAPIFromEnv()
	operations := &operationsAPI{identity: googleIdentity, integrations: loadTenantIntegrationRegistry()}
	mux.HandleFunc("POST /v1/auth/social/google/challenge", googleIdentity.issueGoogleChallenge)
	mux.HandleFunc("POST /v1/auth/social/google", googleIdentity.exchangeGoogleIDToken)
	mux.HandleFunc("GET /v1/me/contexts", googleIdentity.listMyContexts)
	mux.HandleFunc("POST /v1/me/contexts/activate", googleIdentity.activateMyContext)
	mux.HandleFunc("GET /v1/me", googleIdentity.currentContext)
	mux.HandleFunc("POST /v1/auth/logout", googleIdentity.logoutSessionFamily)
	mux.HandleFunc("POST /v1/omisha/isps", googleIdentity.createISPAndOwnerInvitation)
	mux.HandleFunc("POST /v1/me/invitations", googleIdentity.createWorkspaceInvitation)
	mux.HandleFunc("GET /v1/me/invitations", googleIdentity.listWorkspaceInvitations)
	mux.HandleFunc("DELETE /v1/me/invitations/{invitationID}", googleIdentity.revokeWorkspaceInvitation)
	mux.HandleFunc("POST /v1/auth/invitations/redeem", googleIdentity.redeemInvitation)
	mux.HandleFunc("GET /v1/me/isp/acquisitions/{acquisitionID}", operations.getAcquisition)
	mux.HandleFunc("GET /v1/me/isp/service-orders/{serviceOrderID}", operations.getServiceOrder)
	mux.HandleFunc("GET /v1/me/isp/nms/contracts/{number}", operations.getNMSContractReference)
	mux.HandleFunc("GET /v1/me/isp/technician/installation-jobs", operations.listMyInstallationJobs)
	mux.HandleFunc("GET /v1/me/isp/technician/installation-jobs/{jobID}/nms-reference", operations.getInstallationJobNMSReference)
	mux.HandleFunc("/v1/", func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "customer API is not implemented", http.StatusNotImplemented)
	})
	return mux
}

func main() {
	address := os.Getenv("VALKEY_ADDRESS")
	if address == "" {
		address = "valkey:6379"
	}
	server := &http.Server{
		Addr:              ":8080",
		Handler:           handler(address),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    1 << 20,
	}
	log.Fatal(server.ListenAndServe())
}

