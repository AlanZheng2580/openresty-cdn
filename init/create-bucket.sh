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

# 建立 user-a 使用者，匯入自訂 bucket-a policy 並掛給 user-a
mc admin user add local "$BUCKET_A_ACCESS_KEY" "$BUCKET_A_SECRET_KEY"
mc admin policy create local bucketa-readwrite /init/policy-bucket-a.json
mc admin policy attach local bucketa-readwrite --user="$BUCKET_A_ACCESS_KEY"

# 建立 user-b 使用者，匯入自訂 bucket-b policy 並掛給 user-b
mc admin user add local "$BUCKET_B_ACCESS_KEY" "$BUCKET_B_SECRET_KEY"
mc admin policy create local bucketb-readwrite /init/policy-bucket-b.json
mc admin policy attach local bucketb-readwrite --user="$BUCKET_B_ACCESS_KEY"
