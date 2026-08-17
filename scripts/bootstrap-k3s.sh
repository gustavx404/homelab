#!/usr/bin/env bash
# bootstrap-k3s.sh — Provisiona k3s single-node com configuração homelab
# Uso: bash scripts/bootstrap-k3s.sh

set -euo pipefail

echo "=== k3s Bootstrap Homelab ==="

# 1. Verificar se já está instalado
if command -v k3s >/dev/null 2>&1; then
  echo "k3s já instalado: $(k3s --version)"
else
  echo "Instalando k3s..."
  curl -sfL https://get.k3s.io | sh -s - \
    --disable traefik \
    --disable servicelb \
    --disable local-storage \
    --flannel-backend vxlan \
    --cluster-cidr 10.42.0.0/16 \
    --service-cidr 10.43.0.0/16 \
    --cluster-dns 10.43.0.10 \
    --write-kubeconfig-mode 644
fi

# 2. Configurar kubectl
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "KUBECONFIG=$KUBECONFIG"

# 3. Aguardar node ready
echo "Aguardando node Ready..."
kubectl wait --for=condition=Ready node --all --timeout=120s

# 4. Aplicar base (namespaces, storage, networkpolicies)
echo "Aplicando manifests base..."
kubectl apply -k /srv/homelab/k8s/base

# 5. Instalar local-path-provisioner (se não veio com k3s)
echo "Verificando local-path-provisioner..."
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml

# 6. Aguardar StorageClass ready
kubectl wait --for=condition=Ready storageclass local-path --timeout=60s

echo "=== Bootstrap concluído ==="
echo "Próximos passos:"
echo "  1. bash scripts/deploy-secrets.sh    # Aplicar secrets via ksops"
echo "  2. bash scripts/deploy-tailscale.sh  # Tailscale Operator"
echo "  3. bash scripts/deploy-mariadb.sh    # MariaDB StatefulSet"
echo "  4. bash scripts/deploy-traefik.sh    # Traefik + CRDs"
echo "  5. bash scripts/deploy-apps.sh       # Apps core"
