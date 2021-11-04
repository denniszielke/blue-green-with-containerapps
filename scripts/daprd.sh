~/.dapr/bin/placement
~/.dapr/bin/daprd --app-id js-calc-frontend --dapr-http-port 3501 --app-port 8081  --metrics-port 9091 --dapr-grpc-port 50001 --components-path ~/.dapr/components
~/.dapr/bin/daprd --app-id js-calc-backend --dapr-http-port 3502 --app-port 8082  --metrics-port 9092 --dapr-grpc-port 50002