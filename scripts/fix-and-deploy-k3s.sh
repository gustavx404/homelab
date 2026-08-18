#!/usr/bin/env bash
# fix-and-deploy-k3s.sh — Fix k3s systemd unit + deploy all manifests (completo)
# Rode como root: sudo bash /srv/homelab/scripts/fix-and-deploy-k3s.sh

set -euo pipefail

K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
export KUBECONFIG="${K3S_KUBECONFIG}"

echo "=== Fix k3s systemd unit ==="
cat > /etc/systemd/system/k3s.service << 'EOF'
[Unit]
Description=Lightweight Kubernetes
Documentation=https://k3s.io
Wants=network-online.target
After=network-online.target

[Install]
WantedBy=multi-user.target

[Service]
Type=notify
EnvironmentFile=-/etc/default/%N
EnvironmentFile=-/etc/sysconfig/%N
EnvironmentFile=-/etc/systemd/system/k3s.service.env
KillMode=process
Delegate=yes
User=root
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/k3s server \
    --disable=traefik \
    --disable=servicelb \
    --disable=local-storage \
    --flannel-backend=vxlan \
    --cluster-cidr=10.42.0.0/16 \
    --service-cidr=10.43.0.0/16 \
    --cluster-dns=10.43.0.10 \
    --write-kubeconfig-mode=644
EOF

systemctl daemon-reload
systemctl restart k3s

echo "Aguardando k3s ficar ready..."
for i in {1..60}; do
  if kubectl get nodes 2>/dev/null | grep -q "Ready"; then
    echo "k3s Ready!"
    break
  fi
  sleep 2
done

echo "=== Verificando secrets placeholder ==="
if grep -rl "CHANGE_ME" /srv/homelab/k8s/components/*.yaml >/dev/null 2>&1; then
  echo "ERRO: existem senhas placeholder 'CHANGE_ME' em k8s/components/. Edite os Secrets antes de fazer deploy em produção:"
  grep -rl "CHANGE_ME" /srv/homelab/k8s/components/*.yaml
  exit 1
fi

echo "=== Decriptando secrets (sops -> compose/.env) ==="
bash /srv/homelab/scripts/decrypt-secrets.sh

echo "=== Aplicando manifests base + secrets (namespaces, storage, networkpolicies, homelab-secrets) ==="
# --load-restrictor=None é necessário pois compose/.env fica fora da árvore do overlay;
# kubectl apply -k não expõe essa flag, por isso build + apply em dois passos.
kubectl kustomize --load-restrictor=LoadRestrictionsNone /srv/homelab/k8s/overlays/prod | kubectl apply -f -

echo "=== Instalando local-path-provisioner ==="
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml

echo "Aguardando StorageClass..."
kubectl wait --for=condition=Ready storageclass local-path --timeout=120s

echo "=== Instalando Tailscale Operator ==="
kubectl apply -f https://github.com/tailscale/tailscale-operator/releases/latest/download/manifests.yaml

echo "Aguardando Operator..."
kubectl wait --for=condition=Available deployment/tailscale-operator -n kube-system --timeout=120s

echo "=== Deploy MariaDB ==="
kubectl apply -f /srv/homelab/k8s/components/mariadb.yaml

echo "=== Instalando CRDs oficiais do Traefik ==="
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.3/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
kubectl wait --for condition=established --timeout=60s crd/ingressroutes.traefik.io crd/middlewares.traefik.io crd/tlsstores.traefik.io

echo "=== Deploy Traefik ==="
kubectl apply -f /srv/homelab/k8s/components/traefik.yaml

echo "=== Deploy Core Apps ==="
kubectl apply -f /srv/homelab/k8s/components/core-apps.yaml

echo "=== Deploy Monitoring ==="
kubectl apply -f /srv/homelab/k8s/components/monitoring.yaml

echo "=== Deploy Security ==="
kubectl apply -f /srv/homelab/k8s/components/security.yaml

echo "=== Deploy Edge ==="
kubectl apply -f /srv/homelab/k8s/components/edge.yaml

echo "=== Deploy Tailscale Resources (Connector, ProxyGroup, Secret) ==="
kubectl apply -f /srv/homelab/k8s/components/tailscale.yaml

echo "=== Aguardando pods ficarem Ready ==="
for ns in core ai monitoring security media network; do
  echo "Verificando namespace $ns..."
  kubectl wait --for=condition=Ready pod -l app -n "$ns" --timeout=180s 2>/dev/null || true
done

echo "=== Status final ==="
kubectl get pods -A -o wide
echo "---"
kubectl get svc -A
echo "---"
kubectl get ingressroute -A 2>/dev/null || true
echo "---"
kubectl get pvc -A
echo "---"
kubectl get networkpolicy -A

echo "=== Concluído ==="
echo "Para acessar via Tailscale: configure auth key no secret tailscale-auth (namespace network)"
echo "Para DNS local: aponte *.home para o NodePort do Traefik (30080/30443)"