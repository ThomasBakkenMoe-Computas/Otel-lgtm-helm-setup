#!/bin/bash

# Exit on any error
set -e

# Delete the OpenTelemetry Collector Config
#kubectl delete OpenTelemetryCollector otel -n otel

# Uninstall OpenTelemetry Operator
helm uninstall otel-operator -n otel

# Delete the OpenTelemetry namespace
kubectl delete namespace otel

# Uninstall Cert Manager
helm uninstall cert-manager jetstack/cert-manager -n cert-manager

# Remove Helm repos
# helm repo remove jetstack
# helm repo remove open-telemetry

echo "All resources created by bootstrap_observability.sh have been removed."