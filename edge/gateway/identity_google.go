package main

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	"google.golang.org/api/idtoken"
)

const (
	googleChallengeLifetime = 5 * time.Minute
	identitySessionLifetime = 15 * time.Minute
	maxIdentityRequestBytes = 12 * 1024
)

var challengeIDPattern = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)

type googleIdentityAPI struct {
	db        *sql.DB
	audience  string
	hmacKey   []byte
	configErr error
	limiter   *loginRateLimiter
}

func newGoogleIdentityAPIFromEnv() *googleIdentityAPI {
	api := &googleIdentityAPI{audience: strings.TrimSpace(os.Getenv("OMISHA_GOOGLE_SERVER_CLIENT_ID")), limiter: newLoginRateLimiter()}
	dsn, dsnErr := readSecretFile("IDENTITY_DATABASE_URL_FILE")
	key, keyErr := readSecretFile("IDENTITY_HMAC_KEY_FILE")
	if api.audience == "" || dsnErr != nil || keyErr != nil || len(key) < 32 {
		api.configErr = errors.New("identity service configuration is incomplete")
		return api
	}
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		api.configErr = errors.New("identity database configuration is invalid")
		return api
	}
	db.SetMaxOpenConns(12)
	db.SetMaxIdleConns(4)
	db.SetConnMaxIdleTime(5 * time.Minute)
	db.SetConnMaxLifetime(30 * time.Minute)
	api.db = db
	api.hmacKey = []byte(key)
	return api
}

func readSecretFile(name string) (string, error) {
	path := strings.TrimSpace(os.Getenv(name))
	if path == "" {
		return "", errors.New("secret file path is not configured")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	value := strings.TrimSpace(string(data))
	if value == "" {
		return "", errors.New("secret file is empty")
	}
	return value, nil
}

func (api *googleIdentityAPI) issueGoogleChallenge(w http.ResponseWriter, r *http.Request) {
	if api == nil || api.configErr != nil || api.db == nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "sign-in is not configured"})
		return
	}
	if !api.limiter.allow(remoteAddress(r), 12, 10*time.Minute) {
		writeAuthJSON(w, http.StatusTooManyRequests, map[string]string{"error": "try again later"})
		return
	}
	if err := requireEmptyJSONBody(w, r); err != nil {
		writeAuthJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid sign-in request"})
		return
	}
	nonceBytes := make([]byte, 32)
	if _, err := rand.Read(nonceBytes); err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "sign-in is unavailable"})
		return
	}
	nonce := base64.RawURLEncoding.EncodeToString(nonceBytes)
	challengeID, err := randomUUID()
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "sign-in is unavailable"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()
	_, err = api.db.ExecContext(ctx,
		`INSERT INTO auth_challenge_nonces (challenge_id, provider, nonce_hmac, issued_at, expires_at)
		 VALUES ($1, 'google', $2, now(), now() + ($3 * interval '1 second'))`,
		challengeID, keyedDigest(api.hmacKey, "google-challenge-nonce", nonce), int64(googleChallengeLifetime.Seconds()))
	if err != nil {
		log.Printf("Google challenge persistence failed")
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "sign-in is unavailable"})
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeAuthJSON(w, http.StatusCreated, map[string]string{
		"challenge_id": challengeID,
		"nonce":        nonce,
	})
}

func requireEmptyJSONBody(w http.ResponseWriter, r *http.Request) error {
	r.Body = http.MaxBytesReader(w, r.Body, 1024)
	defer r.Body.Close()
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var body struct{}
	if err := decoder.Decode(&body); err != nil {
		return err
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return errors.New("request must contain one JSON object")
	}
	return nil
}

type googleExchangeRequest struct {
	ChallengeID string `json:"challenge_id"`
	Nonce       string `json:"nonce"`
	IDToken     string `json:"id_token"`
}

func (api *googleIdentityAPI) exchangeGoogleIDToken(w http.ResponseWriter, r *http.Request) {
	if api == nil || api.configErr != nil || api.db == nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "sign-in is not configured"})
		return
	}
	if !api.limiter.allow(remoteAddress(r), 12, 10*time.Minute) {
		writeAuthJSON(w, http.StatusTooManyRequests, map[string]string{"error": "try again later"})
		return
	}
	body, err := decodeGoogleExchangeRequest(w, r)
	if err != nil || !challengeIDPattern.MatchString(body.ChallengeID) || len(body.IDToken) < 32 || len(body.IDToken) > 8192 {
		writeAuthJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid sign-in request"})
		return
	}
	nonceBytes, err := base64.RawURLEncoding.DecodeString(body.Nonce)
	if err != nil || len(nonceBytes) != 32 {
		writeAuthJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid sign-in request"})
		return
	}

	verifyCtx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	payload, err := idtoken.Validate(verifyCtx, body.IDToken, api.audience)
	if err != nil || payload == nil || payload.Subject == "" ||
		(payload.Issuer != "accounts.google.com" && payload.Issuer != "https://accounts.google.com") {
		writeAuthJSON(w, http.StatusUnauthorized, map[string]string{"error": "Google sign-in could not be verified"})
		return
	}
	tokenNonce, ok := payload.Claims["nonce"].(string)
	if !ok || !hmac.Equal([]byte(tokenNonce), []byte(body.Nonce)) {
		writeAuthJSON(w, http.StatusUnauthorized, map[string]string{"error": "Google sign-in could not be verified"})
		return
	}

	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "sign-in is unavailable"})
		return
	}
	sessionToken := base64.RawURLEncoding.EncodeToString(tokenBytes)
	sessionID, err := randomUUID()
	if err != nil {
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "sign-in is unavailable"})
		return
	}
	expiresAt := time.Now().UTC().Add(identitySessionLifetime)
	ctx, cancelDB := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancelDB()
	tx, err := api.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		log.Printf("Google identity transaction could not start")
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "sign-in is unavailable"})
		return
	}
	defer tx.Rollback()

	nonceHMAC := keyedDigest(api.hmacKey, "google-challenge-nonce", body.Nonce)
	var consumedID string
	err = tx.QueryRowContext(ctx,
		`UPDATE auth_challenge_nonces
		 SET consumed_at = now()
		 WHERE challenge_id = $1 AND provider = 'google' AND nonce_hmac = $2
		   AND expires_at > now() AND consumed_at IS NULL
		 RETURNING challenge_id`,
		body.ChallengeID, nonceHMAC).Scan(&consumedID)
	if err != nil {
		writeAuthJSON(w, http.StatusUnauthorized, map[string]string{"error": "Google sign-in could not be verified"})
		return
	}

	subjectHMAC := keyedDigest(api.hmacKey, "external-subject/google", payload.Subject)
	identityID, status, err := resolveGoogleIdentity(ctx, tx, subjectHMAC)
	if err != nil {
		log.Printf("Google identity mapping failed")
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "sign-in is unavailable"})
		return
	}
	if status != "active" {
		_ = insertSecurityAudit(ctx, tx, identityID, "auth.google.login", "denied")
		if err := tx.Commit(); err != nil {
			log.Printf("Google denied sign-in audit commit failed")
			writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "sign-in is unavailable"})
			return
		}
		writeAuthJSON(w, http.StatusForbidden, map[string]string{"error": "account access is unavailable"})
		return
	}
	_, err = tx.ExecContext(ctx,
		`INSERT INTO sessions
		 (session_id, identity_id, token_hmac, session_kind, session_family_id, issued_at, expires_at)
		 VALUES ($1, $2, $3, 'identity', $1, now(), $4)`,
		sessionID, identityID, keyedDigest(api.hmacKey, "session-token", sessionToken), expiresAt)
	if err == nil {
		err = insertSecurityAudit(ctx, tx, identityID, "auth.google.login", "success")
	}
	if err != nil {
		log.Printf("Google session persistence failed")
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "sign-in is unavailable"})
		return
	}
	if err := tx.Commit(); err != nil {
		log.Printf("Google session commit failed")
		writeAuthJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "sign-in is unavailable"})
		return
	}

	w.Header().Set("Cache-Control", "no-store")
	writeAuthJSON(w, http.StatusOK, map[string]any{
		"identity_token": sessionToken,
		"expires_at":     expiresAt.Format(time.RFC3339),
	})
}

func decodeGoogleExchangeRequest(w http.ResponseWriter, r *http.Request) (googleExchangeRequest, error) {
	var body googleExchangeRequest
	r.Body = http.MaxBytesReader(w, r.Body, maxIdentityRequestBytes)
	defer r.Body.Close()
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&body); err != nil {
		return body, err
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return body, errors.New("request must contain one JSON object")
	}
	if len(body.Nonce) < 32 || len(body.Nonce) > 256 {
		return body, errors.New("nonce has invalid size")
	}
	return body, nil
}

func resolveGoogleIdentity(ctx context.Context, tx *sql.Tx, subjectHMAC []byte) (string, string, error) {
	// Serialize first-time links for one provider subject. This avoids creating an orphan
	// identity during simultaneous first logins and keeps DELETE out of the runtime grant set.
	if _, err := tx.ExecContext(ctx,
		`SELECT pg_advisory_xact_lock(hashtextextended(encode($1::bytea, 'hex'), 0))`,
		subjectHMAC); err != nil {
		return "", "", err
	}

	var identityID, status string
	err := tx.QueryRowContext(ctx,
		`SELECT i.identity_id::text, i.status
		 FROM external_identities e
		 JOIN identities i ON i.identity_id = e.identity_id
		 WHERE e.provider = 'google' AND e.subject_hmac = $1`,
		subjectHMAC).Scan(&identityID, &status)
	if err == nil {
		return identityID, status, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return "", "", err
	}

	identityID, err = randomUUID()
	if err != nil {
		return "", "", err
	}
	if _, err = tx.ExecContext(ctx,
		`INSERT INTO identities (identity_id, status) VALUES ($1, 'active')`, identityID); err != nil {
		return "", "", err
	}
	if _, err = tx.ExecContext(ctx,
		`INSERT INTO external_identities (provider, subject_hmac, identity_id, verified_at)
		 VALUES ('google', $1, $2, now())`,
		subjectHMAC, identityID); err != nil {
		return "", "", err
	}
	return identityID, "active", nil
}

func insertSecurityAudit(ctx context.Context, tx *sql.Tx, identityID, event, outcome string) error {
	_, err := tx.ExecContext(ctx,
		`INSERT INTO security_audit_events
		 (actor_identity_id, event_code, outcome, metadata)
		 VALUES ($1, $2, $3, '{}'::jsonb)`,
		identityID, event, outcome)
	return err
}

func keyedDigest(key []byte, purpose, value string) []byte {
	mac := hmac.New(sha256.New, key)
	_, _ = mac.Write([]byte(purpose))
	_, _ = mac.Write([]byte{0})
	_, _ = mac.Write([]byte(value))
	return mac.Sum(nil)
}

func randomUUID() (string, error) {
	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	raw[6] = (raw[6] & 0x0f) | 0x40
	raw[8] = (raw[8] & 0x3f) | 0x80
	encoded := hex.EncodeToString(raw)
	return fmt.Sprintf("%s-%s-%s-%s-%s", encoded[:8], encoded[8:12], encoded[12:16], encoded[16:20], encoded[20:]), nil
}

func writeAuthJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func remoteAddress(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

type limitBucket struct {
	windowStart time.Time
	count       int
	lastSeen    time.Time
}

type loginRateLimiter struct {
	mu      sync.Mutex
	buckets map[string]limitBucket
}

func newLoginRateLimiter() *loginRateLimiter {
	return &loginRateLimiter{buckets: make(map[string]limitBucket)}
}

func (l *loginRateLimiter) allow(key string, limit int, window time.Duration) bool {
	if key == "" {
		key = "unknown"
	}
	now := time.Now()
	l.mu.Lock()
	defer l.mu.Unlock()
	if len(l.buckets) >= 4096 {
		for k, bucket := range l.buckets {
			if now.Sub(bucket.lastSeen) > time.Hour {
				delete(l.buckets, k)
			}
		}
		if len(l.buckets) >= 4096 {
			return false
		}
	}
	bucket := l.buckets[key]
	if bucket.windowStart.IsZero() || now.Sub(bucket.windowStart) >= window {
		bucket = limitBucket{windowStart: now, lastSeen: now}
	}
	bucket.lastSeen = now
	bucket.count++
	l.buckets[key] = bucket
	return bucket.count <= limit
}
