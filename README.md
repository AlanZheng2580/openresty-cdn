# OpenResty CDN Proxy with MinIO (Private Bucket)

## 功能說明

- 使用 OpenResty + Lua 作為 CDN Proxy
- 串接 MinIO 私有 bucket，使用 AWS Signature V4 驗證
- MinIO有一組獨立使用者與 access key，設定可存取多個bucket
- 提供 `/minio/<bucket>/<object>` 路由對應私有存取
- 支援多租戶 API Key 驗證，每個 Virtual Host 可指定 API Key 名稱
- API Key 掛載至目錄下，每個檔案就是一把Key
- 使用 Docker Compose 一鍵啟動完整開發環境
- 使用 Makefile 管理常用開發指令
- 附帶 `init/policy-*.json` 限制使用者僅能存取對應 bucket
- 共用簽章邏輯抽出為 `aws_v4_signer.lua`，可於 signer.lua 與 CLI `test_signer.lua` 共用

---

## 📦 專案啟動步驟

1. 複製 `.env` 設定檔：
    ```bash
    cp .env.example .env
    ```

2. 啟動所有服務（含初始化 Bucket 及權限設定）：
    ```bash
    make up
    ```
3. (可選)使用 MinIO 客戶端上傳測試檔案：
    ```bash
    make mc-upload
    ```

4. 使用 curl 測試透過 OpenResty Proxy 存取：
    ```bash
    make curl-test-a  # 應顯示 hello from bucket-a
    make curl-test-b  # 應顯示 hello from bucket-b
    ```

5. 移除所有服務（不會移除MinIO檔案）：
    ```bash
    make down
    ```
---

## 🛠 可用的 Make 指令

| 指令             | 說明 |
|------------------|------|
| `make up`        | 啟動所有 Docker 容器並建置 |
| `make down`      | 停止並移除容器 |
| `make rebuild`   | 只重建 OpenResty 的 Image |
| `make logs`      | 查看 OpenResty 的日誌 |
| `make reload`    | 重新載入nginx.conf，API Key也一併重載入 |
| `make mc-upload` | 手動上傳 `/hello from bucket-X` 測試檔案至兩個 bucket |
| `make curl-test` | 一次測試 bucket-a/bucket-b 的 proxy 存取 |
| `make lua-test`  | 產生curl測試指令，可測試aws簽章 |

---

## 🔐 API Key 驗證機制

- 所有受保護的路由需攜帶 `X-SECDN-API-KEY` header
- 每個 virtual host 可透過 `set $api_key_name` 指定驗證對象
- API Key 會從指定的目錄（由 `SECDN_APIKEY_DIR` 指定）讀入
- 支援 `/api/keys` 查詢目前已載入的 API Key 名稱（不含內容）
---

## 📂 環境變數設定

```bash
SECDN_APIKEY_DIR=${SECDN_APIKEY_DIR}
MINIO_SECRET_KEY=${BUCKET_SECRET_KEY}
```

---

## 📁 專案目錄結構（範例）

```
.
├── docker-compose.yml
├── .env / .env.example
├── Makefile
├── init/
│   ├── create-bucket.sh
│   └── policy-bucket.json  # ➜ 限定 bucketa-key 能存取 bucket-a, bucket-b
├── openresty/
│   ├── apikeys/                    # 每個檔案都是一把API Key（檔名為 key 名）
│   ├── conf/nginx.conf             # 主設定檔
│   └── lua/
│       ├── api_key_auth.lua        # API KEY 驗證模組
│       ├── api_key_check.lua       # API KEY 驗證 handler，給 access_by_lua 呼叫
│       ├── signer.lua              # NGINX 呼叫的 proxy handler
│       ├── test_signer.lua         # CLI 測試 signer 的產出 header 結果
│       └── aws_v4_signer.lua       # ➜ 共用 AWS V4 簽名邏輯模組
└── minio/data/  # 本地 persistent 資料
```

---
## ⚠️ 常見問題：Lua 無法讀取環境變數 `AWS_ACCESS_KEY_ID`

所以如果你在 Lua 中看到這樣的錯誤：

```
Missing AWS credentials
```
請確認 nginx.conf 中有正確設定：

```nginx
set $minio_host "minio:9000";
set $access_key "bucket-key";
set $bucket_name $1;
set $object_key $2;
```

---

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