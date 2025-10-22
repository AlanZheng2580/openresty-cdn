# 載入 .env 內的變數
include .env
export
PROJECT_ROOT := $(shell dirname $(CURDIR)/.)

# 預設指令
.DEFAULT_GOAL := help
LUA_FILES := $(shell find openresty/lua -type f -name "*.lua")
LUA_TEST_FILES := $(shell find test/lua/ -type f -name "*.lua")

.PHONY: help
help:  ## 顯示所有可用指令
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "🛠  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# --- Docker Lifecycle --- #
up: ## 啟動所有服務 (含重建 image)
	docker-compose up --build --remove-orphans

down: ## 停止所有服務
	docker-compose down

rebuild: ## 重建 OpenResty image
	docker-compose build openresty

logs: ## 查看 OpenResty 的 logs
	docker-compose logs -f openresty

bash: ## 進入 OpenResty 容器的 shell
	docker-compose exec openresty bash

reload: check-lua ## 重新載入 OpenResty 設定 (會觸發 Lua 語法檢查)
	docker-compose exec openresty openresty -s reload

# --- Testing --- #
check-lua: ## 檢查所有 Lua 檔案的語法
	@echo "Checking Lua syntax inside Docker..."
	@for file in $(LUA_FILES); do \
		echo "  > $$file"; \
		docker-compose exec openresty  \
			luajit -b "/opt/bitnami/openresty/nginx/lua/$$(basename $$file)" /dev/null || exit 1; \
	done
	@for file in $(LUA_TEST_FILES); do \
		echo "  > $$file"; \
		docker-compose exec openresty  \
			luajit -b "/test/lua/$$(basename $$file)" /dev/null || exit 1; \
	done
	@echo "✅ All Lua files passed."

# docker-compose exec -T openresty resty /test/lua/aws_v4_signer_test.lua
# docker-compose exec -T openresty resty --shdict 'secrets 1m' -e 'require "resty.core"' /test/lua/api_key_auth_test.lua
unit-test: ## [單元測試] 執行 Lua 模組的單元測試
	@docker run --user=0 --rm -v ${PROJECT_ROOT}/test/:/test -v ${PROJECT_ROOT}/openresty/lua:/opt/bitnami/openresty/nginx/lua/  \
	cyching/openresty:20250910-dbddecf6-1.27.1-2-debian-12-r15 bash -c " \
		cd /test; \
		for test_file in \$$(find \"/test/lua\" -type f -iname \"*.lua\"); do \
			echo \"[INFO] Target FIle: \$$test_file\"; \
			resty --shdict 'secrets 1m' -e 'require \"resty.core\"' \"\$$test_file\"; \
			if [ \$$? -ne 0 ]; then \
				echo \"[ERROR] Test '\$$test_file' failed! Exiting.\"; \
				exit 1; \
			fi; \
		done \
	"

curl-test: curl-test-a curl-test-b curl-test-apikey curl-test-cookie curl-test-url-prefix list-api-keys curl-test-cache ## [整合測試] 執行所有 curl 整合測試
	@echo "[SUCCESS] All tests passed!"

curl-test-a: ## [整合測試] 使用 API Key 測試存取 Bucket A
	@curl -s -H "X-SECDN-API-KEY: 58028419ac995b94cc7750b7c5e3a117" https://localhost:8443/minio/${BUCKET_A_NAME}/hello.txt | grep -i "hello from bucket-a"

curl-test-b: ## [整合測試] 使用 API Key 測試存取 Bucket B
	@curl -s -H "X-SECDN-API-KEY: 58028419ac995b94cc7750b7c5e3a117" https://localhost:8443/minio/${BUCKET_B_NAME}/hello.txt | grep -i "hello from bucket-b"

curl-test-apikey: ## [整合測試] 測試 API Key 保護的路由
	@curl -s -H "X-SECDN-API-KEY: 58028419ac995b94cc7750b7c5e3a117" https://localhost:8443/test/apikey | grep -i "apikey ok"
	@curl -s -H "X-SECDN-API-KEY: 58028419ac995b94cc7750b7c5e3a117" https://localhost:8443/test/apikey/minio/${BUCKET_A_NAME}/hello.txt | grep -i "hello from bucket-a"
	@curl -s -H "X-SECDN-API-KEY: 58028419ac995b94cc7750b7c5e3a117" https://localhost:8443/test/apikey/minio/${BUCKET_B_NAME}/hello.txt | grep -i "hello from bucket-b"

# https://localhost:8443/test/
# user-a
# 58028419ac995b94cc7750b7c5e3a117
# 2026-10-20T23:59:59Z
# localhost
curl-test-cookie: ## [整合測試] 測試 Signed Cookie 保護的路由
	@curl -s -H "Cookie: SECDN-CDN-Cookie=URLPrefix=aHR0cHM6Ly9sb2NhbGhvc3Q6ODQ0My90ZXN0Lw==:Expires=1792540799:KeyName=user-a:Signature=5f22bTs1ERvkjx0WOsyDPC19ZwQ=" https://localhost:8443/test/cookie | grep -i "cookie ok"
	@curl -s -H "Cookie: SECDN-CDN-Cookie=URLPrefix=aHR0cHM6Ly9sb2NhbGhvc3Q6ODQ0My90ZXN0Lw==:Expires=1792540799:KeyName=user-a:Signature=5f22bTs1ERvkjx0WOsyDPC19ZwQ=" https://localhost:8443/test/cookie/minio/${BUCKET_A_NAME}/hello.txt | grep -i "hello from bucket-a"
	@curl -s -H "Cookie: SECDN-CDN-Cookie=URLPrefix=aHR0cHM6Ly9sb2NhbGhvc3Q6ODQ0My90ZXN0Lw==:Expires=1792540799:KeyName=user-a:Signature=5f22bTs1ERvkjx0WOsyDPC19ZwQ=" https://localhost:8443/test/cookie/minio/${BUCKET_B_NAME}/hello.txt | grep -i "hello from bucket-b"

curl-test-url-prefix: ## [整合測試] 測試 Signed URL Prefix 保護的路由
	@curl -s "https://localhost:8443/test/signed-url-prefix?URLPrefix=aHR0cHM6Ly9sb2NhbGhvc3Q6ODQ0My90ZXN0Lw==&Expires=1792540799&KeyName=user-a&Signature=YXNGBwGGAijLMu-iuZZgje5b-Vk=" | grep -i "signed url prefix ok"
	@curl -s "https://localhost:8443/test/signed-url-prefix/minio/${BUCKET_A_NAME}/hello.txt?URLPrefix=aHR0cHM6Ly9sb2NhbGhvc3Q6ODQ0My90ZXN0Lw==&Expires=1792540799&KeyName=user-a&Signature=YXNGBwGGAijLMu-iuZZgje5b-Vk=" | grep -i "hello from bucket-a"
	@curl -s "https://localhost:8443/test/signed-url-prefix/minio/${BUCKET_B_NAME}/hello.txt?URLPrefix=aHR0cHM6Ly9sb2NhbGhvc3Q6ODQ0My90ZXN0Lw==&Expires=1792540799&KeyName=user-a&Signature=YXNGBwGGAijLMu-iuZZgje5b-Vk=" | grep -i "hello from bucket-b"
	@curl -s "https://localhost:8443/test/signed-url-prefix/get?URLPrefix=aHR0cHM6Ly9sb2NhbGhvc3Q6ODQ0My90ZXN0Lw==&Expires=1792540799&KeyName=user-a&Signature=YXNGBwGGAijLMu-iuZZgje5b-Vk="|grep '"args": {},'

curl-test-cache: ## [整合測試] 測試快取功能 (HIT/MISS/PURGE)
	sleep 3
	@curl -Is https://localhost:8443/get | grep -i "X-Cache-Status:"
	@curl -Is https://localhost:8443/get | grep -i "X-Cache-Status: HIT"
	@curl -Is https://localhost:8443/purge/get | grep -i "HTTP/1.1 200 OK"
	@curl -Is https://localhost:8443/get | grep -i "X-Cache-Status: MISS"
	@curl -Is https://localhost:8443/get | grep -i "X-Cache-Status: HIT"
	@curl -Is -X PURGE https://localhost:8443/ | grep -i "HTTP/1.1 200 OK"
	@curl -Is https://localhost:8443/get | grep -i "X-Cache-Status: MISS"
	@curl -Is https://localhost:8443/get | grep -i "X-Cache-Status: HIT"
	@curl -s https://localhost:8443/status | grep -i "<title>nginx vhost traffic status monitor</title>"

# --- Benchmarking --- #
ab-install: ## 安裝 Apache Benchmark (ab) 工具
	@echo "Installing Apache Benchmark (ab)..."
	@sudo apt-get update
	@sudo apt-get install -y apache2-utils

ab-test-apikey: ## [壓力測試] 測試 API Key 保護的路由
	@ab -n 100000 -c 50 -H "X-SECDN-API-KEY: 58028419ac995b94cc7750b7c5e3a117" "http://localhost:8080/test/apikey"

ab-test-minio: ## [壓力測試] 測試 MinIO 直連路由
	@ab -n 100000 -c 50 "http://localhost:8080/test/minio/hello.txt"

ab-test-all: ## [壓力測試] 測試 API Key + MinIO 路由
	@ab -n 100000 -c 50 -H "X-SECDN-API-KEY: 58028419ac995b94cc7750b7c5e3a117" "http://localhost:8080/test/all/hello.txt"

ab-test-lualog: ## [壓力測試] 測試 LUA Log
	@ab -n 100000 -c 50 "http://localhost:8080/lualog?URLPrefix=aHR0cHM6Ly9sb2NhbGhvc3Q6ODQ0My90ZXN0Lw==&Expires=1792540799&KeyName=user-a&Signature=YXNGBwGGAijLMu-iuZZgje5b-Vk="

benchmark_signer: ## [效能測試] 執行 AWS V4 簽章效能測試
	curl "http://localhost:8080/benchmark_signer?n=100000"

benchmark_timer: ## [效能測試] 執行 Lua 計時器效能測試
	curl "http://localhost:8080/benchmark_timer"

# --- Utilities --- #
list-api-keys: ## [工具] 列出所有已載入的 API Keys
	@curl -s -H "X-SECDN-API-KEY: 01234567890123456789012345678901" https://localhost:8443/api/keys

gen-curl-cmd: ## [工具] 產生用於測試 AWS 簽章的 curl 指令
	docker exec openresty-cdn_openresty_1 bash -c "cd /opt/bitnami/openresty/nginx/lua/ && TEST_ACCESS_KEY=${BUCKET_ACCESS_KEY} TEST_SECRET_KEY=${BUCKET_SECRET_KEY} TEST_MINIO_HOST=minio:9000 TEST_BUCKET=${BUCKET_A_NAME} TEST_OBJECT=hello.txt resty test_signer.lua"

gen-api-key: ## [工具] 產生一個新的 16-byte API Key
	openssl rand -hex 16

mc-upload: ## [工具] 上傳測試檔案到 MinIO 私有 bucket
	echo "hello from bucket-a" > /tmp/hello-a.txt
	echo "hello from bucket-b" > /tmp/hello-b.txt
	
	docker run --rm --network host \
	-e MC_HOST_local="http://$(MINIO_ROOT_USER):$(MINIO_ROOT_PASSWORD)@localhost:9000" \
	-v /tmp:/tmp \
	minio/mc cp /tmp/hello-a.txt local/$(BUCKET_A_NAME)/hello.txt

	docker run --rm --network host \
	-e MC_HOST_local="http://$(MINIO_ROOT_USER):$(MINIO_ROOT_PASSWORD)@localhost:9000" \
	-v /tmp:/tmp \
	minio/mc cp /tmp/hello-b.txt local/$(BUCKET_B_NAME)/hello.txt



