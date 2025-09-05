### **認證 API 功能說明文件**

**API 端點:** `http://js-auth:2345/auth` (內部服務，由 OpenResty 代理)

**功能:**
此 API 用於驗證傳入請求的授權資訊。它會檢查請求頭中的 `Authorization` 和 `Cookie`，以及其他轉發資訊（如 `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Host`, `X-Forwarded-Method`, `X-Forwarded-Uri`, `User-Agent`），以確定請求是否合法。

**使用方式:**

OpenResty 服務會作為代理，將特定路徑（例如 `/test/apiauth` 或 `/minio/apiauth/`）的請求轉發到此內部認證 API。

**請求方法:**
`GET`

**請求頭 (由 OpenResty 轉發):**

*   `Authorization`: 包含認證憑證 (例如 API Key 或 Bearer Token)。
*   `Cookie`: 包含會話相關的 Cookie。
*   `X-Real-IP`: 客戶端的真實 IP 地址。
*   `X-Forwarded-For`: 請求的轉發路徑中的客戶端 IP 地址。
*   `X-Forwarded-Host`: 原始請求的主機名。
*   `X-Forwarded-Method`: 原始請求的 HTTP 方法。
*   `X-Forwarded-Uri`: 原始請求的 URI。
*   `User-Agent`: 請求的用戶代理，此處固定為 `SECDN-API-CHECK/1.0`。

**回應:**

*   **成功 (2xx 狀態碼):**
    *   如果認證成功，API 會返回一個 2xx 狀態碼 (例如 200 OK)。
    *   OpenResty 會繼續處理原始請求。
*   **失敗 (非 2xx 狀態碼):**
    *   如果認證失敗，API 會返回一個非 2xx 狀態碼 (例如 401 Unauthorized)。
    *   OpenResty 會攔截請求，返回 401 Unauthorized 狀態碼，並在回應體中包含錯誤訊息。

**錯誤處理:**

*   **連接錯誤:** 如果 OpenResty 無法連接到認證 API (例如網路問題或服務不可用)，它會嘗試重試 3 次。如果重試失敗，OpenResty 會返回 503 Service Unavailable。
*   **認證 API 錯誤:** 如果認證 API 返回非 2xx 狀態碼，OpenResty 會記錄警告訊息，並返回 401 Unauthorized。

**範例 (OpenResty 配置):**

```nginx
location /test/apiauth {
    set $secdn_auth_request_url "http://js-auth:2345/auth";
    access_by_lua_file lua/api_check.lua;
    echo "/test/apiauth, API Auth is valid";
}
```

**注意事項:**

*   此 API 是一個內部服務，不應直接從外部訪問。
*   `api_check.lua` 腳本負責處理與此認證 API 的通訊、重試邏輯和錯誤處理。
