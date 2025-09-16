package main

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"html/template"
	"net/http"
	"strings"
	"time"
)

type PageData struct {
	URLPrefix    string
	KeyName      string
	Key          string
	Expiration   string
	Domain       string
	SignedCookie string
	SignedURL    string
	CurlCommand  string
}

func main() {
	http.HandleFunc("/", homeHandler)
	http.ListenAndServe(":1234", nil)
}

// homeHandler handles the form on the homepage.
func homeHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodPost {
		urlPrefix := r.FormValue("urlPrefix")
		keyName := r.FormValue("keyName")
		keyHex := r.FormValue("key")
		expirationStr := r.FormValue("expiration")
		domain := r.FormValue("domain")

		// Convert expiration to time.Time
		expiration, err := time.Parse("2006-01-02T15:04:05Z", expirationStr)
		if err != nil {
			http.Error(w, "Invalid expiration format. Use the format 'YYYY-MM-DDTHH:MM:SSZ'.", http.StatusBadRequest)
			return
		}

		// Convert the hex key to byte slice
		key, err := hex.DecodeString(keyHex)
		if err != nil {
			http.Error(w, "Invalid key format. Ensure it's a valid hex string.", http.StatusBadRequest)
			return
		}
		if len(key) != 16 {
			http.Error(w, "Key must be 16 bytes long.", http.StatusBadRequest)
			return
		}

		// Generate signed cookie
		signedCookie, err := signCookie(urlPrefix, keyName, key, expiration)
		if err != nil {
			http.Error(w, fmt.Sprintf("Error generating signed cookie: %v", err), http.StatusInternalServerError)
			return
		}

		// Generate the curl command
		curlCommand := fmt.Sprintf(`curl -v -H "Cookie: SECDN-CDN-Cookie=%s" %s`, signedCookie, urlPrefix)

		// Generate signed URL
		signedURL, err := signURLWithPrefix(urlPrefix, keyName, key, expiration)
		if err != nil {
			http.Error(w, fmt.Sprintf("Error generating signed URL: %v", err), http.StatusInternalServerError)
			return
		}

		// Set the cookie in the response
		http.SetCookie(w, &http.Cookie{
			Name:     "SECDN-CDN-Cookie",
			Value:    signedCookie,
			Path:     "/",
			Expires:  expiration,
			Domain:   domain,
			HttpOnly: true,
		})

		// Render the template with the data
		data := PageData{
			URLPrefix:    urlPrefix,
			KeyName:      keyName,
			Key:          keyHex,
			Expiration:   expirationStr,
			Domain:       domain,
			SignedCookie: signedCookie,
			SignedURL:    signedURL,
			CurlCommand:  curlCommand,
		}

		tmpl := template.Must(template.New("home").Parse(homePageTemplate))
		tmpl.Execute(w, data)
		return
	}

	// Display the form for the first time
	tmpl := template.Must(template.New("home").Parse(homePageTemplate))
	tmpl.Execute(w, nil)
}

// signCookie creates a signed cookie for an endpoint served by SECDN CDN.
//
// - urlPrefix must start with "https://" and should include the path prefix
// for which the cookie will authorize access to.
// - key should be in raw form (not base64url-encoded) which is
// 16-bytes long.
// - keyName must match a key added to the backend service or bucket.
func signCookie(urlPrefix, keyName string, key []byte, expiration time.Time) (string, error) {
	encodedURLPrefix := base64.URLEncoding.EncodeToString([]byte(urlPrefix))
	input := fmt.Sprintf("URLPrefix=%s:Expires=%d:KeyName=%s",
		encodedURLPrefix, expiration.Unix(), keyName)

	mac := hmac.New(sha1.New, key)
	mac.Write([]byte(input))
	sig := base64.URLEncoding.EncodeToString(mac.Sum(nil))

	signedValue := fmt.Sprintf("%s:Signature=%s",
		input,
		sig,
	)

	return signedValue, nil
}

// SignURLWithPrefix creates a signed URL prefix for an endpoint on Cloud CDN.
// Prefixes allow access to any URL with the same prefix, and can be useful for
// granting access broader content without signing multiple URLs.
//
// - urlPrefix must start with "https://" and should not include query parameters.
// - key should be in raw form (not base64url-encoded) which is 16-bytes long.
// - keyName must match a key added to the backend service or bucket.
func signURLWithPrefix(urlPrefix, keyName string, key []byte, expiration time.Time) (string, error) {
	if strings.Contains(urlPrefix, "?") {
		return "", fmt.Errorf("urlPrefix must not include query params: %s", urlPrefix)
	}

	encodedURLPrefix := base64.URLEncoding.EncodeToString([]byte(urlPrefix))
	input := fmt.Sprintf("URLPrefix=%s&Expires=%d&KeyName=%s",
		encodedURLPrefix, expiration.Unix(), keyName)

	mac := hmac.New(sha1.New, key)
	mac.Write([]byte(input))
	sig := base64.URLEncoding.EncodeToString(mac.Sum(nil))

	signedValue := fmt.Sprintf("%s&Signature=%s", input, sig)

	return signedValue, nil
}

// HTML template for the home page
const homePageTemplate = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SECDN CDN Cookie Generator</title>
</head>
<body>
    <h1>SECDN CDN Cookie Generator</h1>
    <form method="POST" action="/">
        <label for="urlPrefix">URL Prefix (e.g., http://localhost:8080/test/cookie/ok):</label><br>
        <input type="text" id="urlPrefix" name="urlPrefix" value="{{.URLPrefix}}" style="width: 500px;" required><br><br>

        <label for="keyName">Key Name (e.g., user-a):</label><br>
        <input type="text" id="keyName" name="keyName" value="{{.KeyName}}" style="width: 500px;" required><br><br>

        <label for="key">Key (16-byte hex string)(e.g., 58028419ac995b94cc7750b7c5e3a117):</label><br>
        <input type="text" id="key" name="key" value="{{.Key}}" style="width: 500px;" required><br><br>

        <label for="expiration">Expiration (e.g., 2025-06-20T23:59:59Z):</label><br>
        <input type="text" id="expiration" name="expiration" value="{{.Expiration}}" style="width: 500px;" required><br><br>

		<label for="domain">Domain (e.g., localhost):</label><br>
        <input type="text" id="domain" name="domain" value="{{.Domain}}" style="width: 500px;" required><br><br>

        <button type="submit">Generate/Set Cookie</button>
    </form>

    {{if .SignedCookie}}
    <h2>Generated Cookie</h2>
    <p><strong>Signed Cookie:</strong></p>
    <pre>{{.SignedCookie}}</pre>

    <h2>Generated cURL Command</h2>
    <p><strong>cURL Command:</strong></p>
    <pre>{{.CurlCommand}}</pre>

	<h2>Redirect to Test Page</h2>
	<form action="" method="GET" onsubmit="window.open(document.getElementById('urlInput').value, '_blank'); return false;">
		<input type="text" id="urlInput" name="url" value="{{.URLPrefix}}" style="width: 500px;"/><br>
		<button type="submit">Go to Test Page with Cookie</button>
	</form>
    {{end}}

	{{if .SignedURL}}
    <h2>Generated SignedURL</h2>
    <p><strong>Signed URL:</strong></p>
    <pre>{{.SignedURL}}</pre>
	{{end}}

</body>
</html>
`
