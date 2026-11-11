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
    "strings"
    "time"
)

var ErrTenant = errors.New("integration tenant mismatch")
var ErrUpstream = errors.New("upstream request failed")
var ErrNotFound = errors.New("integration record not found")
var ErrAmbiguous = errors.New("integration record is ambiguous")
var label = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$`)
var document = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9 ._-]{0,139}$`)
var positiveID = regexp.MustCompile(`^[1-9][0-9]{0,18}$`)
var frappeUser = regexp.MustCompile(`^[A-Za-z0-9._%+@-]{1,140}$`)

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


// AcquisitionProjection is a bounded workflow view from the owning Frappe site.
// It intentionally excludes Lead/customer contact fields and financial payloads.
type AcquisitionProjection struct {
    Name string `json:"name"`
    RequestedPlan string `json:"requested_plan"`
    Status string `json:"acquisition_status"`
    IdentityStatus string `json:"identity_status"`
    PaymentRequest string `json:"payment_request"`
    ServiceOrder string `json:"service_order"`
}

// Acquisition reads only fields required to render onboarding progress in the BFF.
func (c *Client) Acquisition(ctx context.Context, tenant, name string) (AcquisitionProjection, error) {
    var result AcquisitionProjection
    if c.kind != "frappe" || !document.MatchString(name) {
        return result, errors.New("invalid acquisition request")
    }
    fields, _ := json.Marshal([]string{
        "name", "requested_plan", "acquisition_status", "identity_status",
        "payment_request", "service_order",
    })
    query := url.Values{}
    query.Set("fields", string(fields))
    path := "/api/resource/ISP%20Acquisition%20Request/" + url.PathEscape(name) + "?" + query.Encode()
    raw, err := c.read(ctx, tenant, path)
    if err != nil {
        return result, err
    }
    var envelope struct {
        Data AcquisitionProjection `json:"data"`
    }
    if json.Unmarshal(raw, &envelope) != nil || envelope.Data.Name != name {
        return result, ErrUpstream
    }
    return envelope.Data, nil
}

// ServiceOrder reads a limited operational projection from the client Frappe site.
type ServiceOrderProjection struct {
	Name              string `json:"name"`
	RequestedPlan     string `json:"requested_plan"`
	ServiceStatus     string `json:"service_status"`
	ExternalServiceID string `json:"external_service_id"`
}

// InstallationJobProjection is a small technician queue view. It deliberately
// excludes subscriber contact details and returns only ERP-owned installation fields.
type InstallationJobProjection struct {
	Name string `json:"name"`
	AcquisitionRequest string `json:"acquisition_request"`
	Outcome string `json:"installation_outcome"`
	ONTVendor string `json:"ont_vendor"`
	ONTModel string `json:"ont_model"`
	ONTSerial string `json:"ont_serial"`
	ONTMAC string `json:"ont_mac"`
	OLTReference string `json:"olt_reference"`
	FiberConnected int `json:"fiber_connected"`
	ONTPowered int `json:"ont_powered"`
	OpticalTestPassed int `json:"optical_test_passed"`
	OpticalRXDBM *float64 `json:"optical_rx_dbm"`
	WANLinkUp int `json:"wan_link_up"`
	FailureCode string `json:"failure_code"`
	Docstatus int `json:"docstatus"`
}

// AssignedInstallationJobs returns at most 50 open jobs assigned to one
// operator-mapped Frappe user. The caller must derive the user mapping server-side.
func (c *Client) AssignedInstallationJobs(ctx context.Context, tenant, user string) ([]InstallationJobProjection, error) {
	if c.kind != "frappe" || !frappeUser.MatchString(user) {
		return nil, errors.New("invalid technician mapping")
	}
	fields, _ := json.Marshal([]string{"name", "acquisition_request", "installation_outcome", "ont_vendor", "ont_model", "ont_serial", "ont_mac", "olt_reference", "fiber_connected", "ont_powered", "optical_test_passed", "optical_rx_dbm", "wan_link_up", "failure_code", "docstatus"})
	filters, _ := json.Marshal([][]any{{"assigned_technician", "=", user}, {"docstatus", "=", 0}})
	query := url.Values{}
	query.Set("fields", string(fields))
	query.Set("filters", string(filters))
	query.Set("limit_page_length", "50")
	query.Set("order_by", "modified asc")
	raw, err := c.read(ctx, tenant, "/api/resource/ISP%20Installation%20Job?"+query.Encode())
	if err != nil { return nil, err }
	var envelope struct { Data []InstallationJobProjection `json:"data"` }
	if json.Unmarshal(raw, &envelope) != nil || len(envelope.Data) > 50 { return nil, ErrUpstream }
	for _, job := range envelope.Data {
		if !document.MatchString(job.Name) || !document.MatchString(job.AcquisitionRequest) || job.Docstatus != 0 { return nil, ErrUpstream }
	}
	return envelope.Data, nil
}

func (c *Client) ServiceOrder(ctx context.Context, tenant, name string) (ServiceOrderProjection, error) {
	var result ServiceOrderProjection
	if c.kind != "frappe" || !document.MatchString(name) {
		return result, errors.New("invalid service order request")
	}
	fields, _ := json.Marshal([]string{
		"name", "requested_plan", "service_status", "external_service_id",
	})
	query := url.Values{}
	query.Set("fields", string(fields))
	raw, err := c.read(ctx, tenant, "/api/resource/ISP%20Service%20Order/"+url.PathEscape(name)+"?"+query.Encode())
	if err != nil {
		return result, err
	}
	var envelope struct {
		Data ServiceOrderProjection `json:"data"`
	}
	if json.Unmarshal(raw, &envelope) != nil || envelope.Data.Name != name {
		return result, ErrUpstream
	}
	return envelope.Data, nil
}

type nmsObjectReference struct {
    ID int64 `json:"id"`
    Number string `json:"number"`
    MAC string `json:"mac"`
    ContractID int64 `json:"contract_id"`
}

// ContractIDByNumber uses NMS Prime's documented Contract filter. More than one
// match fails closed. It returns only an internal object reference, not PII.
func (c *Client) ContractIDByNumber(ctx context.Context, tenant, number string) (int64, error) {
    if c.kind != "nms" || !label.MatchString(number) {
        return 0, errors.New("invalid NMS contract lookup")
    }
    query := url.Values{}
    query.Set("number", number)
    raw, err := c.read(ctx, tenant, "/admin/api/v0/Contract?"+query.Encode())
    if err != nil {
        return 0, err
    }
    var envelope struct {
        Models map[string]nmsObjectReference `json:"models"`
    }
    if json.Unmarshal(raw, &envelope) != nil {
        return 0, ErrUpstream
    }
    var match *nmsObjectReference
    for _, item := range envelope.Models {
        if item.Number != number {
            continue
        }
        if match != nil || item.ID <= 0 {
            return 0, ErrAmbiguous
        }
        copy := item
        match = &copy
    }
    if match == nil {
        return 0, ErrNotFound
    }
    return match.ID, nil
}

// ModemIDByMAC finds one modem/CPE by its exact MAC and returns only its ID.
// It is a lookup, not proof of ownership or authorization for a user request.
func (c *Client) ModemIDByMAC(ctx context.Context, tenant, mac string) (int64, error) {
    if c.kind != "nms" || !regexp.MustCompile(`(?i)^([0-9a-f]{2}:){5}[0-9a-f]{2}$`).MatchString(mac) {
        return 0, errors.New("invalid NMS modem lookup")
    }
    query := url.Values{}
    query.Set("mac", mac)
    raw, err := c.read(ctx, tenant, "/admin/api/v0/Modem?"+query.Encode())
    if err != nil {
        return 0, err
    }
    var envelope struct {
        Models map[string]nmsObjectReference `json:"models"`
    }
    if json.Unmarshal(raw, &envelope) != nil {
        return 0, ErrUpstream
    }
    var match *nmsObjectReference
    for _, item := range envelope.Models {
        if !strings.EqualFold(item.MAC, mac) {
            continue
        }
        if match != nil || item.ID <= 0 {
            return 0, ErrAmbiguous
        }
        copy := item
        match = &copy
    }
    if match == nil {
        return 0, ErrNotFound
    }
    return match.ID, nil
}
