# OpenResty CDN Proxy with MinIO (Private Bucket)

## 功能說明

- 使用 OpenResty + Lua 作為 CDN Proxy
- 串接 MinIO 私有 bucket，使用 AWS Signature V4 驗證
- 每個 bucket 對應一組獨立使用者與 access key
- 提供 `/bucket-a/<object>` 與 `/bucket-b/<object>` 路由對應私有存取
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
    make curl-bucket-a  # 應顯示 hello from bucket-a
    make curl-bucket-b  # 應顯示 hello from bucket-b
    ```

---

## 🛠 可用的 Make 指令

| 指令             | 說明 |
|------------------|------|
| `make up`        | 啟動所有 Docker 容器並建置 |
| `make down`      | 停止並移除容器 |
| `make rebuild`   | 只重建 OpenResty 的 Image |
| `make logs`      | 查看 OpenResty 的日誌 |
| `make mc-upload` | 手動上傳 `/etc/hosts` 測試檔案至兩個 bucket |
| `make curl-test` | 一次測試 bucket-a/bucket-b 的 proxy 存取 |

---

## ⚠️ 常見問題：Lua 無法讀取環境變數 `AWS_ACCESS_KEY_ID`

> ⚠️ 本專案已移除對 `os.getenv("AWS_ACCESS_KEY_ID")` 的依賴，所有 AWS key 都透過 `nginx.conf` 傳入 Lua。

所以如果你在 Lua 中看到這樣的錯誤：

```
Missing AWS credentials
```
請確認 nginx.conf 中有正確設定：

```nginx
set $minio_host "minio:9000";
set $access_key "bucketa-key";
set $secret_key "bucketa-secret";
set $bucket_name "bucket-a";
set $object_key $1;  # 從 rewrite 或 if 拿到物件 key
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
│   ├── policy-bucket-a.json  # ➜ 限定 bucketa-key 只能存取 bucket-a
│   └── policy-bucket-b.json  # ➜ 限定 bucketb-key 只能存取 bucket-b
├── openresty/
│   ├── conf/nginx.conf
│   └── lua/
│       ├── signer.lua              # NGINX 呼叫的 proxy handler
│       ├── test_signer.lua         # CLI 測試 signer 的產出 header 結果
│       └── aws_v4_signer.lua       # ➜ 共用 AWS V4 簽名邏輯模組
└── minio/data/  # 本地 persistent 資料
```
