# 載入 .env 內的變數
include .env
export

# 預設指令
.DEFAULT_GOAL := help

.PHONY: help
help:  ## 顯示所有可用指令
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "🛠  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

up: ## 啟動所有服務
	docker-compose up --build

down: ## 停止所有服務
	docker-compose down

logs: ## 查看 OpenResty 的 logs
	docker-compose logs -f openresty

reload:
	docker-compose exec openresty openresty -s reload

rebuild: ## 重建 OpenResty image
	docker-compose build openresty

list-api-keys:
	curl -H "X-SECDN-API-KEY: 01234567890123456789012345678901" http://localhost:8080/api/keys
	
curl-test-a:
	curl -H "X-SECDN-API-KEY: 58028419ac995b94cc7750b7c5e3a117" http://localhost:8080/minio/${BUCKET_A_NAME}/hello.txt

curl-test-b:
	curl -H "X-SECDN-API-KEY: 58028419ac995b94cc7750b7c5e3a117" http://localhost:8080/minio/${BUCKET_B_NAME}/hello.txt

curl-test: curl-test-a curl-test-b list-api-keys

ab-test-apikey: 
	@ab -n 100000 -c 50 -H "X-SECDN-API-KEY: 58028419ac995b94cc7750b7c5e3a117" "http://localhost:8080/test/apikey"

ab-test-minio: 
	@ab -n 100000 -c 50 "http://localhost:8080/test/minio/hello.txt"

ab-test-all: 
	@ab -n 100000 -c 50 -H "X-SECDN-API-KEY: 58028419ac995b94cc7750b7c5e3a117" "http://localhost:8080/test/all/hello.txt"

ab-install:
	@echo "Installing Apache Benchmark (ab)..."
	@sudo apt-get update
	@sudo apt-get install -y apache2-utils

lua-test: ## 產生curl指令
	docker exec openresty-cdn_openresty_1 bash -c "cd /opt/bitnami/openresty/nginx/lua/ && TEST_ACCESS_KEY=${BUCKET_ACCESS_KEY} TEST_SECRET_KEY=${BUCKET_SECRET_KEY} TEST_MINIO_HOST=minio:9000 TEST_BUCKET=${BUCKET_A_NAME} TEST_OBJECT=hello.txt resty test_signer.lua"

mc-upload: ## 上傳一個測試檔案到 MinIO 私有 bucket
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

gen-api-key:
	openssl rand -hex 16

benchmark_signer:
	curl "http://localhost:8080/benchmark_signer?n=100000"

benchmark_timer:
	curl "http://localhost:8080/benchmark_timer"
