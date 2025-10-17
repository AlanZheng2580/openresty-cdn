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

## 啟用本機 HTTPS (SSL)

本專案支援透過 HTTPS 進行本地開發，但需要手動產生並信任本機的 SSL 憑證。我們使用 `mkcert` 這個工具來簡化此流程。

### 1. 安裝 mkcert

請根據您的作業系統選擇安裝方式：

- **macOS (使用 [Homebrew](https://brew.sh/))**
  ```bash
  brew install mkcert
  ```

- **Linux (以 Debian/Ubuntu 為例)**
  首先安裝 `certutil` 工具：
  ```bash
  sudo apt install libnss3-tools
  wget "$(curl -s https://api.github.com/repos/FiloSottile/mkcert/releases/latest | grep browser_download_url | grep 'linux-amd64' | cut -d '"' -f 4)" -O mkcert
  chmod +x ./mkcert
  sudo mv ./mkcert /usr/local/bin/
  mkcert --version
  ```

### 2. 安裝本機 CA (Certificate Authority)

安裝完 `mkcert` 後，執行以下指令來建立並安裝一個本地的憑證頒發機構。這會讓您本機產生的憑證被瀏覽器自動信任。

```bash
mkcert -install
```
(此步驟可能需要輸入您的系統密碼)

### 3. 產生憑證檔案

進入專案根目錄，執行以下指令來為 `localhost` 產生憑證。

```bash
mkcert -key-file openresty/certs/localhost-key.pem -cert-file openresty/certs/localhost.pem localhost 127.0.0.1 ::1
```

完成後，`openresty/certs` 目錄下就會有 `localhost.pem` 和 `localhost-key.pem` 兩個檔案。接著您就可以透過 `https://localhost:8443` 存取服務了。

---

## 🛠 可用的 Make 指令

執行 `make help` 來查看所有可用的指令及其說明。

```bash
make help
```

---

## 🔐 存取驗證機制 (Access Authentication Mechanisms)

本專案提供三種驗證方式來保護您的資源：

### 1. API Key Header

這是最基本的驗證方式。客戶端需在請求的 Header 中攜帶 `X-SECDN-API-KEY`，其值必須符合預設的 API Key。

- **適用情境**: 伺服器對伺服器的內部服務呼叫。
- **設定方式**: 在 `nginx.conf` 的 location 區塊中，透過 `set $api_key_name "your-key-name";` 指定要驗證的 Key 名稱，並使用 `access_by_lua_file /path/to/api_key_check.lua;` 啟用驗證。

### 2. Signed Cookie (URL Prefix)

此方法模仿 Google Cloud CDN 的 Signed Cookie 功能，提供有時效性的授權，可用於保護一組檔案。

- **運作方式**:
    1. 後端服務需預先產生一個特殊的 Cookie (`SECDN-CDN-Cookie`) 給客戶端。
    2. 此 Cookie 包含 `URLPrefix` (Base64編碼的網址前綴)、`Expires` (過期時間)、`KeyName` (金鑰名稱) 以及 `Signature` (HMAC-SHA1簽章)。
    3. OpenResty 會驗證此 Cookie 的簽章是否有效、是否過期，以及請求的網址是否符合 `URLPrefix` 的範圍。
- **簽章產生**: 簽章的內容是將 `URLPrefix`、`Expires`、`KeyName` 三個欄位的值用冒號 (`:`) 串接而成。
- **適用情境**: 保護網站上的特定目錄，讓通過驗證的瀏覽器使用者可以在一段時間內存取底下的所有資源。

### 3. Signed URL (URL Prefix)

此方法與 Signed Cookie 類似，但將驗證資訊直接放在 URL 的查詢參數中。

- **運作方式**:
    1. 後端服務需預先產生帶有簽章的 URL。
    2. URL 需包含 `URLPrefix`、`Expires`、`KeyName`、`Signature` 四個查詢參數。
    3. OpenResty 會驗證簽章、過期時間與 `URLPrefix`。
    4. 驗證成功後，這四個驗證參數會從查詢字串中移除，再將請求轉發至後端服務。
    5. 原始的完整請求網址 (包含簽章) 會被放在 `X-Client-Request-URL` header 中，一併轉發至後端，供後端選擇性驗證。
- **簽章產生**: 簽章的內容是將 `URLPrefix`、`Expires`、`KeyName` 三個欄位的值用 `&` 符號串接而成。
- **適用情境**: 提供給使用者或客戶端一個有時效性的獨立網址，用於下載特定資源或一組資源。

---

## 📝 日誌記錄 (Logging)

為了安全起見，本專案的 Nginx 存取日誌 (`access_log`) 會自動對敏感資訊進行過濾。

- **簽章過濾**: 當請求的網址包含 `Signature` 查詢參數時，其值在日誌中會被替換為 `[MASKED]`。這可以防止包含完整簽章的有效網址被記錄下來，避免日誌外洩時可能造成的安全風險。
---

## 🧪 測試 (Testing)

本專案包含整合測試與單元測試，可透過 `make` 指令執行。

### 整合測試

執行 `make curl-test` 來對目前運行的服務進行一系列的 `curl` 請求測試，驗證各種驗證機制是否正常運作。

### 單元測試

執行 `make unit-test` 來針對核心的 Lua 模組進行單元測試。

**重要**: 這些測試是在 Docker 容器內執行的。在執行測試之前，特別是在修改程式碼後，建議先執行 `make up` 來確保 Docker image 已被重建且環境是最新狀態。

```bash
# 1. 確保 Docker 服務正在運行
make up

# 2. 執行單元測試
make unit-test
```

---

## 🧪 Next.js 播放器 (CORS 測試)

專案內附一個 Next.js 應用程式，可用於在瀏覽器環境中實際測試 CDN 的 CORS 設定以及兩種驗證方式。
已包成Docker Image整入，若想單獨測試，可用下列指令本機執行

### 啟動步驟

1. **進入播放器目錄**
   ```bash
   cd test/nextjs-player
   ```

2. **安裝依賴套件** (若尚未安裝)
   ```bash
   npm install
   ```

3. **啟動開發伺服器**
   ```bash
   npm run dev
   ```

4. **開啟瀏覽器**
   - 前往 `http://localhost:3000`

### 如何使用

- **M3U8 URL**: 在此輸入您要播放的影片完整路徑，例如 `http://localhost:8080/minio/bucket-a/path/to/your/video.m3u8`。
- **Auth Method**: 選擇您要使用的驗證方式。
  - **API Key**: 使用簡單的 API 金鑰驗證，需在下方輸入框填入對應的 `X-SECDN-API-KEY`。
  - **Token**: 使用 HMAC 簽章驗證，需在下方輸入框填入完整的 `X-SECDN-Token`。
- **Load Video**: 點擊按鈕以套用設定並開始播放影片。

如果影片無法播放，請務必打開瀏覽器的開發人員工具 (F12) 查看 **Console** 和 **Network** 分頁中的錯誤訊息。

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