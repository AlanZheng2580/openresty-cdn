package main

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/go-redis/redis/v8"
	"golang.org/x/net/context"
)

const (
	openRestyURL = "http://localhost:8080"
	redisAddr    = "localhost:6379"
	activeUsersKey = "waiting_room:active_users"
	queueKey       = "waiting_room:queue"
	maxActiveUsers = 3 // Assuming this is configured in OpenResty
)

var (
	rdb *redis.Client
	ctx = context.Background()
)

func TestMain(m *testing.M) {
	// Start Docker Compose
	fmt.Println("Starting Docker Compose...")
	cmd := exec.Command("docker-compose", "up", "-d", "--build")
	cmd.Dir = "/home/alan/workspace/tsmc/openresty-cdn" // Absolute path to project root
	output, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("Error starting Docker Compose: %s\n%s\n", err, string(output))
		os.Exit(1)
	}
	fmt.Println("Docker Compose started.")

	// Initialize Redis client
	rdb = redis.NewClient(&redis.Options{
		Addr: redisAddr,
	})

	// Wait for OpenResty and Redis to be ready
	if err := waitForService(openRestyURL); err != nil {
		fmt.Printf("OpenResty not ready: %v\n", err)
		shutdownDockerCompose()
		os.Exit(1)
	}
	if err := waitForRedis(rdb); err != nil {
		fmt.Printf("Redis not ready: %v\n", err)
		shutdownDockerCompose()
		os.Exit(1)
	}
	fmt.Println("OpenResty and Redis are ready.")

	// Run tests
	code := m.Run()

	// Shutdown Docker Compose
	fmt.Println("Shutting down Docker Compose...")
	shutdownDockerCompose()

	os.Exit(code)
}

func shutdownDockerCompose() {
	cmd := exec.Command("docker-compose", "down")
	cmd.Dir = "/home/alan/workspace/tsmc/openresty-cdn" // Absolute path to project root
	output, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("Error shutting down Docker Compose: %s\n%s\n", err, string(output))
	}
}

func waitForService(url string) error {
	for i := 0; i < 60; i++ { // Try for 60 seconds
		resp, err := http.Get(url)
		if err == nil && resp.StatusCode == http.StatusOK {
			resp.Body.Close()
			return nil
		}
		if resp != nil {
			resp.Body.Close()
		}
		time.Sleep(1 * time.Second)
	}
	return fmt.Errorf("service at %s not ready", url)
}

func waitForRedis(client *redis.Client) error {
	for i := 0; i < 60; i++ { // Try for 60 seconds
		_, err := client.Ping(ctx).Result()
		if err == nil {
			return nil
		}
		time.Sleep(1 * time.Second)
	}
	return fmt.Errorf("redis at %s not ready", client.Options().Addr)
}

func clearRedisKeys() {
	rdb.Del(ctx, activeUsersKey, queueKey).Result()
}

func get(t *testing.T, url string, cookie string) (*http.Response, string, string) {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		t.Fatalf("Failed to create request: %v", err)
	}
	if cookie != "" {
		req.Header.Set("Cookie", cookie)
	}

	client := &http.Client{
		Timeout: 5 * time.Second, // Add a timeout for the HTTP client
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse // Don't follow redirects automatically
		},
	}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("Failed to perform GET request: %v", err)
	}
	defer resp.Body.Close()

	bodyBytes, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("Failed to read response body: %v", err)
	}
	bodyString := string(bodyBytes)

	setCookie := resp.Header.Get("Set-Cookie")
	return resp, bodyString, setCookie
}

func extractCookie(setCookieHeader string, name string) string {
	parts := strings.Split(setCookieHeader, ";")
	for _, part := range parts {
		if strings.HasPrefix(strings.TrimSpace(part), name+"=") {
			return strings.TrimPrefix(strings.TrimSpace(part), name+"=")
		}
	}
	return ""
}

func TestWaitingRoom_ConcurrentUsersAndQueue(t *testing.T) {
	clearRedisKeys()

	var wg sync.WaitGroup
	userCookies := make(chan string, maxActiveUsers) // Channel to store session IDs of active users

	// Simulate MAX_ACTIVE_USERS concurrent users
	for i := 0; i < maxActiveUsers; i++ {
		wg.Add(1)
		go func(userNum int) {
			defer wg.Done()
			t.Logf("User %d: Starting access.", userNum)
			var currentCookie string // To store the session ID for this specific user
			// Keep accessing the main site to simulate active users
			for j := 0; j < 5; j++ { // Make a few requests to ensure they are active
				resp, body, setCookie := get(t, openRestyURL+"/", currentCookie)
				t.Logf("User %d: Request %d, Status: %d, Body contains httpbin: %t", userNum, j+1, resp.StatusCode, strings.Contains(body, "httpbin"))
				if resp.StatusCode != http.StatusOK {
					t.Errorf("User %d: Expected status OK, got %d. Body: %s", userNum, resp.StatusCode, body)
					return
				}
				if !strings.Contains(body, "httpbin") {
					t.Errorf("User %d: Expected body to contain 'httpbin', got: %s", userNum, body)
					return
				}
				if currentCookie == "" { // Only extract cookie on first request
					sessionID := extractCookie(setCookie, "wr_session_id")
					if sessionID == "" {
						t.Errorf("User %d: Failed to get session ID on first request.", userNum)
						return
					}
					currentCookie = "wr_session_id=" + sessionID
					userCookies <- currentCookie // Send the cookie back to the main goroutine
				}
				time.Sleep(100 * time.Millisecond) // Simulate some delay between requests
			}
			t.Logf("User %d: Finished active access simulation.", userNum)
		}(i + 1)
	}

	// Wait for all initial users to get their session IDs
	for i := 0; i < maxActiveUsers; i++ {
		<-userCookies
	}
	close(userCookies) // Close the channel as we won't send more cookies

	// Give a moment for Redis to update with active users
	time.Sleep(1 * time.Second)

	// Now, a new user (the 4th) should be redirected to the waiting room
	t.Log("Simulating 4th user access.")
	resp, body, setCookie := get(t, openRestyURL+"/", "")

	if resp.StatusCode != 302 {
		t.Errorf("Expected status %d (Moved Temporarily), got %d. Body: %s", 302, resp.StatusCode, body)
	}
	if resp.Header.Get("Location") != "/waiting_room.html" {
		t.Errorf("Expected redirect to /waiting_room.html, got %s", resp.Header.Get("Location"))
	}
	wrSessionID := extractCookie(setCookie, "wr_session_id")
	if wrSessionID == "" {
		t.Error("Expected wr_session_id cookie to be set for 4th user, but it was empty.")
	}

	// Verify 4th user is added to queue in Redis
	queueUsers, err := rdb.ZRange(ctx, queueKey, 0, -1).Result()
	if err != nil {
		t.Fatalf("Failed to get queue users from Redis: %v", err)
	}
	if len(queueUsers) != 1 || queueUsers[0] != wrSessionID {
		t.Errorf("Expected 1 user in queue (%s), got: %v", wrSessionID, queueUsers)
	}

	// Wait for all goroutines to finish
	wg.Wait()
	t.Log("All users finished.")
}
