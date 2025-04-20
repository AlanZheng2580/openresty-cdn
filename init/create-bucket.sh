#!/bin/sh

sleep 5

mc alias set local http://minio:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD

# 建立 bucket（若尚未存在）
if mc ls local | grep -q "$MINIO_BUCKET"; then
  echo "Bucket $MINIO_BUCKET already exists"
else
  mc mb local/$MINIO_BUCKET
  echo "✅ Bucket $MINIO_BUCKET created"
fi

# 建立 hello.txt 測試檔案（每次都覆蓋）
echo "Hello from MinIO!" > /tmp/hello.txt
mc cp /tmp/hello.txt local/$MINIO_BUCKET/hello.txt
echo "✅ hello.txt uploaded to $MINIO_BUCKET"
