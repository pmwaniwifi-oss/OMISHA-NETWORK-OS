package integrations

import (
    "context"
    "errors"
    "net/http"
    "net/http/httptest"
    "strings"
    "testing"
)

func fixture(t *testing.T, kind string, handler http.HandlerFunc) *Client {
    t.Helper()
    server := httptest.NewTLSServer(handler)
    t.Cleanup(server.Close)
    var c *Client
    var err error
    if kind == "frappe" { c, err = NewFrappe("tenant1", server.URL, "key", "secret")
    } else { c, err = NewNMSPrime("tenant1", server.URL, "api@example.test", "secret") }
    if err != nil { t.Fatal(err) }
    // Trust only this test server's certificate; preserve production redirect policy.
    c.http.Transport = server.Client().Transport
    return c
}

func TestFrappeContractAndTenant(t *testing.T) {
    calls:=0
    c:=fixture(t,"frappe",func(w http.ResponseWriter,r *http.Request){
        calls++
        if r.Method!="GET" || r.URL.Path!="/api/resource/Customer/CUST 001" || r.Header.Get("Authorization")!="token key:secret" { t.Error("incorrect Frappe request") }
        w.Write([]byte(`{"data":{"name":"CUST 001"}}`))
    })
    if _,err:=c.Customer(context.Background(),"tenant2","CUST 001"); !errors.Is(err,ErrTenant) { t.Fatal(err) }
    if calls!=0 { t.Fatal("foreign tenant reached upstream") }
    if _,err:=c.Customer(context.Background(),"tenant1","CUST 001");err!=nil{t.Fatal(err)}
}

func TestNMSContract(t *testing.T) {
    c:=fixture(t,"nms",func(w http.ResponseWriter,r *http.Request){
        user,pass,ok:=r.BasicAuth()
        if !ok || user!="api@example.test" || pass!="secret" || r.URL.Path!="/admin/api/v0/Contract/12" { t.Error("incorrect NMS request") }
        w.Write([]byte(`{"success":true,"models":{"12":{"id":12}}}`))
    })
    if _,err:=c.Contract(context.Background(),"tenant1","12");err!=nil{t.Fatal(err)}
    for _,id:=range []string{"../12","12/restart","0","-1"}{ if _,err:=c.Contract(context.Background(),"tenant1",id);err==nil{t.Fatal("accepted unsafe ID")}}
}

func TestRedirectDoesNotLeakCredentials(t *testing.T) {
    reached:=false
    target:=httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){reached=true}))
    defer target.Close()
    c:=fixture(t,"frappe",func(w http.ResponseWriter,r *http.Request){http.Redirect(w,r,target.URL,302)})
    if _,err:=c.Customer(context.Background(),"tenant1","C1");err==nil{t.Fatal("accepted redirect")}
    if reached{t.Fatal("followed redirect")}
}

func TestInvalidResponsesFailClosed(t *testing.T) {
    for _,body:=range []string{`not json`,`[]`,`{"data":null}`,`{"exception":"secret details"}`,strings.Repeat("x",(2<<20)+1)}{
        c:=fixture(t,"frappe",func(w http.ResponseWriter,r *http.Request){w.Write([]byte(body))})
        _,err:=c.Customer(context.Background(),"tenant1","C1")
        if !errors.Is(err,ErrUpstream){t.Fatal("invalid response accepted")}
        if strings.Contains(err.Error(),"secret details"){t.Fatal("leaked upstream body")}
    }
    c:=fixture(t,"nms",func(w http.ResponseWriter,r *http.Request){w.Write([]byte(`{"success":false,"models":{}}`))})
    if _,err:=c.Contract(context.Background(),"tenant1","1");!errors.Is(err,ErrUpstream){t.Fatal(err)}
}

func TestUnsafeConfiguration(t *testing.T) {
    for _,origin:=range []string{"http://example.test","https://user:pass@example.test","https://example.test/path","https://example.test?x=1"}{
        if _,err:=NewFrappe("t1",origin,"key","secret");err==nil{t.Fatal("accepted unsafe origin")}
    }
}

func TestCancellation(t *testing.T) {
    c:=fixture(t,"frappe",func(w http.ResponseWriter,r *http.Request){t.Error("cancelled call reached server")})
    ctx,cancel:=context.WithCancel(context.Background());cancel()
    if _,err:=c.Customer(ctx,"tenant1","C1");!errors.Is(err,ErrUpstream){t.Fatal(err)}
}
