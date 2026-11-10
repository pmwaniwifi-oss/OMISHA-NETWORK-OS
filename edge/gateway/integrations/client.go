// Package integrations contains server-side, read-only clients. It does not
// expose routes or authenticate end users. Configuration is operator-controlled.
package integrations

import (
    "context"
    "encoding/base64"
    "encoding/json"
    "errors"
    "fmt"
    "io"
    "net/http"
    "net/url"
    "regexp"
    "time"
)

var ErrTenant = errors.New("integration tenant mismatch")
var ErrUpstream = errors.New("upstream request failed")
var label = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$`)
var document = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9 ._-]{0,139}$`)
var positiveID = regexp.MustCompile(`^[1-9][0-9]{0,18}$`)

type Client struct {
    tenant string
    origin string
    authorization string
    kind string
    http *http.Client
}

func newClient(tenant, origin, authorization, kind string) (*Client, error) {
    u, err := url.Parse(origin)
    if err != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil ||
        (u.Path != "" && u.Path != "/") || u.RawQuery != "" || u.Fragment != "" || !label.MatchString(tenant) {
        return nil, errors.New("tenant and HTTPS origin required")
    }
    u.Path = ""
    return &Client{tenant: tenant, origin: u.String(), authorization: authorization, kind: kind,
        http: &http.Client{Timeout: 10*time.Second, CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
            return http.ErrUseLastResponse
        }}}, nil
}

func NewFrappe(tenant, origin, apiKey, apiSecret string) (*Client, error) {
    if !label.MatchString(apiKey) || !label.MatchString(apiSecret) {
        return nil, errors.New("invalid Frappe API credential format")
    }
    return newClient(tenant, origin, "token "+apiKey+":"+apiSecret, "frappe")
}

func NewNMSPrime(tenant, origin, username, password string) (*Client, error) {
    if username == "" || password == "" || len(username)>254 || len(password)>1024 {
        return nil, errors.New("NMS API credentials required")
    }
    for _, char := range username { if char == ':' || char < 32 || char == 127 { return nil, errors.New("invalid username") } }
    return newClient(tenant, origin, "Basic "+base64.StdEncoding.EncodeToString([]byte(username+":"+password)), "nms")
}

func (c *Client) read(ctx context.Context, tenant, path string) (json.RawMessage, error) {
    if tenant != c.tenant { return nil, ErrTenant }
    req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.origin+path, nil)
    if err != nil { return nil, ErrUpstream }
    req.Header.Set("Authorization", c.authorization)
    req.Header.Set("Accept", "application/json")
    response, err := c.http.Do(req)
    if err != nil { return nil, ErrUpstream } // do not return URL, credentials or upstream body
    defer response.Body.Close()
    if response.StatusCode != http.StatusOK { return nil, fmt.Errorf("%w: HTTP %d", ErrUpstream, response.StatusCode) }
    const maximum = 2 << 20
    body, err := io.ReadAll(io.LimitReader(response.Body, maximum+1))
    if err != nil || len(body)>maximum || !json.Valid(body) { return nil, ErrUpstream }
    var envelope map[string]json.RawMessage
    if json.Unmarshal(body, &envelope) != nil || envelope == nil { return nil, ErrUpstream }
    if c.kind == "frappe" {
        data, exists := envelope["data"]
        if !exists || string(data)=="null" { return nil, ErrUpstream }
    } else {
        var success bool
        if json.Unmarshal(envelope["success"], &success) != nil || !success || envelope["models"] == nil {
            return nil, ErrUpstream
        }
    }
    return body, nil
}

// Customer fetches one known ERPNext Customer. Name-to-subscriber ownership must
// be resolved by the authenticated BFF; this function is not a customer portal.
func (c *Client) Customer(ctx context.Context, tenant, name string) (json.RawMessage, error) {
    if c.kind != "frappe" || !document.MatchString(name) { return nil, errors.New("invalid customer request") }
    return c.read(ctx, tenant, "/api/resource/Customer/"+url.PathEscape(name))
}

// Contract uses the pinned NMS BaseRoute admin/api/v0 resource convention.
// Never accept arbitrary action paths: upstream also has GET routes that mutate devices.
func (c *Client) Contract(ctx context.Context, tenant, id string) (json.RawMessage, error) {
    if c.kind != "nms" || !positiveID.MatchString(id) { return nil, errors.New("invalid contract request") }
    return c.read(ctx, tenant, "/admin/api/v0/Contract/"+id)
}
