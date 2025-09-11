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
