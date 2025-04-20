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

rebuild: ## 重建 OpenResty image
	docker-compose build openresty

curl-test: ## 測試 curl 調用 OpenResty 代理的 MinIO 私有檔案
	curl -v http://localhost:8080/media/$(MINIO_BUCKET)/hello.txt

mc-upload: ## 上傳一個測試檔案到 MinIO 私有 bucket
	docker run --rm --network host \
	-e MC_HOST_local="http://$(MINIO_ROOT_USER):$(MINIO_ROOT_PASSWORD)@localhost:9000" \
	minio/mc cp /etc/hosts local/$(MINIO_BUCKET)/hello.txt
