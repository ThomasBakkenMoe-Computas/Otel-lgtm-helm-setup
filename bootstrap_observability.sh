#!/bin/bash

# Exit on any error
set -e

# Add required Helm repos
echo "Adding required Helm repos..."
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Cert-Manager
helm upgrade \
  --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.15.3 \
  --set crds.enabled=true

# Install OpenTelemetry Operator
helm upgrade --install otel-operator open-telemetry/opentelemetry-operator --namespace otel --create-namespace \
    --set "manager.collectorImage.repository=otel/opentelemetry-collector-k8s" \
    --set admissionWebhooks.certManager.enabled=true \

# Wait for the webhook service to be ready
echo "Waiting for the OpenTelemetry Operator webhook service to be ready (20 seconds)..."
sleep 20  # Wait for 20 seconds

# Create Otel Collector Config
kubectl apply -f - <<EOF
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: otel
  namespace: otel
spec:
  image: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.109.0
  mode: deployment
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
          http:
      prometheus:
        config:
          scrape_configs:
            - job_name: 'otel-collector'
              scrape_interval: 10s
              static_configs:
                - targets: [ '0.0.0.0:8888' ]
    
    processors:
      batch:
      memory_limiter:
        check_interval: 1s
        limit_percentage: 50
        spike_limit_percentage: 30
    
    exporters:
      otlp:
        endpoint: "http://tempo.otel.svc.cluster.local:55680"
        tls:
          insecure: true
      otlphttp/mimir:
        endpoint: "http://mimir.otel.svc.cluster.local:8080/otlp"
      loki:
        endpoint: "http://loki.otel.svc.cluster.local:3100/loki/api/v1/push"
      logging:
    
    service:
      # Expose internal telemetry of the collector
      # It exposes Prometheus /metrics endpoint, that is scraped by the prometheus receiver
      # and the metrics are sent through the pipeline to the metrics backend.
      telemetry:
        metrics:
          address: localhost:8888
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [otlp]
        metrics:
          receivers: [prometheus, otlp]
          processors: [memory_limiter, batch]
          exporters: [otlphttp/mimir]
        logs:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [loki, logging]
EOF

# Install grafana
helm upgrade --install grafana grafana/grafana --namespace monitoring --create-namespace -f grafana-values.yaml


# Install Loki
helm upgrade --install loki grafana/loki-distributed --namespace monitoring --create-namespace -f loki-values.yaml

# Install Tempo
helm upgrade --install tempo grafana/tempo-distributed --namespace monitoring --create-namespace -f tempo-values.yaml


# helm upgrade lgtm-distributed grafana/lgtm-distributed --namespace observability --create-namespace