#!/bin/sh
set -x 

sleep 3

mc alias set local http://minio:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD

# 建立 bucket-a
mc mb --ignore-existing local/$BUCKET_A_NAME
echo "hello from bucket-a" > /tmp/hello-a.txt
mc cp /tmp/hello-a.txt local/$BUCKET_A_NAME/hello.txt

# 建立 bucket-b
mc mb --ignore-existing local/$BUCKET_B_NAME
echo "hello from bucket-b" > /tmp/hello-b.txt
mc cp /tmp/hello-b.txt local/$BUCKET_B_NAME/hello.txt

# 建立 user 使用者，匯入自訂 bucket policy 並掛給 user
mc admin user add local "$BUCKET_ACCESS_KEY" "$BUCKET_SECRET_KEY"
mc admin policy create local bucketa-readwrite /init/policy-bucket.json
mc admin policy attach local bucketa-readwrite --user="$BUCKET_ACCESS_KEY"
