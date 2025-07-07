# 虛擬等候室功能測試指南

本指南提供了測試 OpenResty 虛擬等候室功能的步驟。

## 1. 啟動服務

確保您的 Docker 服務已啟動，包括 `openresty` 和 `redis`。

```bash
docker-compose up -d openresty redis
```

## 2. 清除 Redis 數據 (可選，用於全新測試)

如果您想從一個乾淨的狀態開始測試，可以清除 Redis 中的所有數據。

**方法一：手動進入 Redis 容器執行命令 (推薦)**

1.  進入 Redis 容器：
    ```bash
    docker-compose exec redis sh
    ```
2.  在容器內執行 `FLUSHALL`：
    ```bash
    redis-cli FLUSHALL
    ```
3.  退出容器：
    ```bash
    exit
    ```

**方法二：重啟 Redis 服務 (會清除數據)**

```bash
docker-compose restart redis
```

## 3. 觀察 OpenResty 日誌

在一個單獨的終端窗口中，運行以下命令來實時查看 OpenResty 的日誌。這將是您判斷功能是否正確的關鍵。

```bash
docker-compose logs -f openresty
```

## 4. 模擬用戶訪問並觀察行為

使用 `curl` 命令模擬用戶訪問。每次模擬新用戶時，請確保清除 `Cookie`，以避免使用相同的會話 ID。

### 測試場景 A: 活躍用戶數未達上限

模擬一個新用戶訪問。您應該會看到 HTTP 200 響應 (來自 `httpbin`)，並且在 OpenResty 日誌中會顯示用戶被授予訪問權限。

```bash
curl -v -H "Cookie:" http://localhost:8080/
```

**預期日誌輸出 (OpenResty):**
*   `[HANDLE] Processing session_id: ...`
*   `[HANDLE] User status for ...: nil`
*   `[HANDLE] New user or unknown status for ...`
*   `[HANDLE] Current active_users: <N>, max_users: 10` (其中 N < 10)
*   `[HANDLE] Granting access to ...`

### 測試場景 B: 活躍用戶數達到上限

重複執行 `curl` 命令，直到活躍用戶數達到 `VWR_MAX_USERS` (預設為 10)。之後的用戶訪問應該會被重定向到等候頁面。

```bash
# 重複執行此命令，直到您在日誌中看到用戶被加入等待隊列
curl -v -H "Cookie:" http://localhost:8080/
```

**預期 `curl` 輸出 (當達到上限時):**
*   HTTP 狀態碼為 `302 Moved Temporarily`
*   `Location: /waiting-room.html`

**預期日誌輸出 (OpenResty):**
*   `[HANDLE] Current active_users: 10, max_users: 10`
*   `[HANDLE] Site full. Adding ... to waiting queue.`

### 測試場景 C: 訪問等候頁面

模擬用戶直接訪問等候頁面。

```bash
curl http://localhost:8080/waiting-room.html
```

**預期 `curl` 輸出:**
*   返回 `waiting-room.html` 的 HTML 內容。

### 測試場景 D: 檢查用戶狀態 API

使用之前被重定向到等候頁面的用戶的 `vwr_session_id` (從 `curl -v` 的 `Set-Cookie` 頭部獲取)，檢查其狀態。

```bash
curl -H "Cookie: vwr_session_id=<YOUR_SESSION_ID>" http://localhost:8080/waiting-room/status
```

**預期 `curl` 輸出:**
*   `{"status":"waiting"}`

### 測試場景 E: 活躍用戶減少後，等待用戶是否被提升

由於無法直接在 CLI 中模擬會話超時，您可以手動減少 Redis 中的 `vwr:active_users` 值，或者等待 `session_timeout` (預設 15 分鐘) 讓活躍用戶過期。

**手動減少活躍用戶數 (在 Redis 容器內執行):**

1.  進入 Redis 容器：
    ```bash
    docker-compose exec redis sh
    ```
2.  減少活躍用戶數 (例如，減少 1 個):
    ```bash
    redis-cli DECR vwr:active_users
    ```
3.  退出容器：
    ```bash
    exit
    ```

**然後，模擬一個新的用戶請求 (即使這個用戶會被重定向到等候頁面，它也會觸發 `promote_waiting_users`):**

```bash
curl -s -o /dev/null -H "Cookie:" http://localhost:8080/
```

**預期日誌輸出 (OpenResty):**
*   `[PROMOTION] Starting promote_waiting_users`
*   `[PROMOTION] Promoting user: ...` (如果等待隊列中有用戶且有空閒槽位)

---

希望這份測試指南對您有所幫助！如果您在測試過程中遇到任何問題或有其他疑問，請隨時提出。
