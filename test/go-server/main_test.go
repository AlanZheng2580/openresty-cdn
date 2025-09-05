package main

import (
	"encoding/hex"
	
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

// TestSignCookie tests the signCookie function with a set of known values.
func TestSignCookie(t *testing.T) {
	// Test case based on a known pre-calculated signature
	urlPrefix := "https://example.com/path/"
	keyName := "my-key"
	// 16-byte key, "0123456789abcdef" in string form
	key, _ := hex.DecodeString("30313233343536373839616263646566")
	// 2025-12-25T00:00:00Z
	expiration := time.Date(2025, time.December, 25, 0, 0, 0, 0, time.UTC) 

	// This is the pre-calculated expected output
	expectedSignedValue := "URLPrefix=aHR0cHM6Ly9leGFtcGxlLmNvbS9wYXRoLw==:Expires=1766620800:KeyName=my-key:Signature=2zvL1ekf2bM9gygp1dmsu-8hsbA="

	signedValue, err := signCookie(urlPrefix, keyName, key, expiration)
	if err != nil {
		t.Fatalf("signCookie returned an unexpected error: %v", err)
	}

	if signedValue != expectedSignedValue {
		t.Errorf("signCookie returned incorrect signature.\nExpected: %s\nGot:      %s", expectedSignedValue, signedValue)
	}
}

// TestHomeHandlerGet tests the GET request handling of homeHandler.
func TestHomeHandlerGet(t *testing.T) {
	req, err := http.NewRequest("GET", "/", nil)
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(homeHandler)

	handler.ServeHTTP(rr, req)

	// Check the status code
	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v",
			status, http.StatusOK)
	}

	// Check if the response body contains the form title
	expected := "SECDN CDN Cookie Generator"
	if !strings.Contains(rr.Body.String(), expected) {
		t.Errorf("handler returned unexpected body: got %v want to contain %q",
			rr.Body.String(), expected)
	}
}

// TestHomeHandlerPostSuccess tests the POST request handling of homeHandler with valid data.
func TestHomeHandlerPostSuccess(t *testing.T) {
	form := url.Values{}
	form.Add("urlPrefix", "http://localhost:8080/test/cookie/ok")
	form.Add("keyName", "user-a")
	form.Add("key", "58028419ac995b94cc7750b7c5e3a117")
	form.Add("expiration", "2025-06-20T23:59:59Z")
	form.Add("domain", "localhost")

	req, err := http.NewRequest("POST", "/", strings.NewReader(form.Encode()))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Add("Content-Type", "application/x-www-form-urlencoded")

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(homeHandler)

	handler.ServeHTTP(rr, req)

	// Check the status code
	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v",
			status, http.StatusOK)
	}

	// Check if the Set-Cookie header is present
	if cookie := rr.Header().Get("Set-Cookie"); cookie == "" {
		t.Errorf("handler did not set the 'Set-Cookie' header")
	}

	// Check if the curl command is in the body
	if !strings.Contains(rr.Body.String(), "curl -v -H &#34;Cookie: SECDN-CDN-Cookie=") {
		t.Errorf("handler response did not contain the curl command. Body: %s", rr.Body.String())
	}
}

// TestHomeHandlerPostInvalidData tests the POST request handling with invalid data.
func TestHomeHandlerPostInvalidData(t *testing.T) {
	testCases := []struct {
		name          string
		formData      url.Values
		expectedError string
	}{
		{
			"Invalid Expiration",
			url.Values{
				"urlPrefix":  {"http://localhost"},
				"keyName":    {"user-a"},
				"key":        {"58028419ac995b94cc7750b7c5e3a117"},
				"expiration": {"not-a-date"},
				"domain":     {"localhost"},
			},
			"Invalid expiration format",
		},
		{
			"Invalid Key Hex",
			url.Values{
				"urlPrefix":  {"http://localhost"},
				"keyName":    {"user-a"},
				"key":        {"not-a-hex-string"},
				"expiration": {"2025-06-20T23:59:59Z"},
				"domain":     {"localhost"},
			},
			"Invalid key format",
		},
		{
			"Invalid Key Length",
			url.Values{
				"urlPrefix":  {"http://localhost"},
				"keyName":    {"user-a"},
				"key":        {"deadbeef"}, // 4 bytes, not 16
				"expiration": {"2025-06-20T23:59:59Z"},
				"domain":     {"localhost"},
			},
			"Key must be 16 bytes long",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			req, err := http.NewRequest("POST", "/", strings.NewReader(tc.formData.Encode()))
			if err != nil {
				t.Fatal(err)
			}
			req.Header.Add("Content-Type", "application/x-www-form-urlencoded")

			rr := httptest.NewRecorder()
			handler := http.HandlerFunc(homeHandler)

			handler.ServeHTTP(rr, req)

			if status := rr.Code; status != http.StatusBadRequest {
				t.Errorf("handler returned wrong status code: got %v want %v",
					status, http.StatusBadRequest)
			}

			if !strings.Contains(rr.Body.String(), tc.expectedError) {
				t.Errorf("handler returned unexpected body: got %q, want to contain %q",
					rr.Body.String(), tc.expectedError)
			}
		})
	}
}