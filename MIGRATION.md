# Migração: Docker Compose → Kubernetes

Guia de referência para migrar este homelab (20 containers via Docker
Compose) para Kubernetes. É um prompt/brief pronto para ser entregue a
quem for executar a migração — humano ou agente. O `compose/*.yaml` atual
é a fonte da verdade sobre o comportamento esperado de cada serviço;
este documento resume o que existe e aponta onde a migração exige
decisão explícita em vez de um port 1:1.

## Inventário atual (20 containers → precisam virar workloads k8s)

| Serviço | Imagem | Workload sugerido | Observação crítica |
|---|---|---|---|
| traefik | traefik:v3.3 | Deployment | provider hoje é `docker.sock` — vira CRD provider do k8s |
| tailscale | tailscale/tailscale:latest | — | **substituir** pelo Tailscale Operator, não portar como container |
| mariadb | mariadb:lts | StatefulSet + PVC | banco central de 5 apps (HA, Forgejo, CrowdSec, Mumble, Vaultwarden) |
| homeassistant | homeassistant:stable | Deployment + PVC | usa `recorder` no MariaDB |
| esphome | esphome:stable | Deployment | **hoje `network_mode: host`** (mDNS/discovery ESP32) |
| frigate | frigate (pin sha256) | Deployment + PVC | pode precisar de Coral TPU / GPU passthrough |
| forgejo | forgejo:16.0.2 | Deployment + PVC | porta SSH 2222 exposta |
| vaultwarden | vaultwarden:1.37.1 | Deployment + PVC | só acessível via Traefik hoje |
| mumble | mumblevoip/mumble-server | Deployment | TCP+UDP 64738 |
| omniroute | omniroute:latest | Deployment | gateway de IA |
| redis | redis:8.6.5-alpine | Deployment | cache do omniroute |
| prometheus | prom/prometheus:v3.4.0 | Deployment + PVC | 5 scrape jobs hardcoded por nome de container |
| grafana | grafana:11.6.0 | Deployment + PVC | backend MySQL no MariaDB central |
| suricata | suricata:latest | **DaemonSet ou hostNetwork** | **captura tráfego bruto (AF_PACKET) em `eno1` e `br-homelab` — não roda em pod comum** |
| crowdsec | crowdsecurity/crowdsec:latest | Deployment | consome `eve.json` do Suricata; **sem bouncer local hoje** (bloqueio acontece num roteador OpenWrt fora do repo) |
| suricata-stats | build local (distroless) | Deployment | lê o mesmo `eve.json` do Suricata — acoplado a ele |
| kali | kalilinux/kali-rolling | ⚠️ decidir | roda 24/7 com `NET_RAW`+`NET_ADMIN` — avaliar Job sob demanda em vez de sempre ativo |
| ts-forgejo / ts-homeassistant / ts-vaultwarden | tailscale/tailscale:latest | — | sidecars Tailscale Serve/Funnel — **substituir pelo Tailscale Operator** |

## Decisões de arquitetura a tomar ANTES de escrever qualquer manifest

1. **Distribuição k8s**: para homelab single-node, `k3s` é o caminho de
   menor atrito (Traefik e local-path-provisioner já vêm inclusos).
   Confirme single-node vs multi-node — muda a resposta do item 3.
2. **CNI e isolamento de rede**: hoje existe uma única rede bridge
   (`backend`) isolando tudo do host. Recrie esse isolamento com
   `NetworkPolicy` — "estar no mesmo cluster" não é isolamento.
3. **Storage**: hoje são bind mounts em `../data/<serviço>`. Escolha uma
   `StorageClass` (local-path-provisioner é o mínimo viável; considere
   Longhorn se quiser replicação/snapshot).
4. **Secrets**: hoje é SOPS+age (`compose/sops-secrets.yaml`, chave
   pública em `.sops.yaml`). Duas opções realistas:
   - manter SOPS+age via plugin `ksops` do Kustomize (menor mudança de fluxo)
   - migrar para External Secrets Operator ou Sealed Secrets
   Qualquer opção: **nenhum valor em texto puro nos manifests**.
5. **Ingress**: Traefik tem CRDs nativas de k8s (`IngressRoute`,
   `Middleware`) — reaproveite o conhecimento já existente do time.
6. **GitOps**: o repo já trata infra como código. Recomendo Flux CD ou
   Argo CD aplicando os manifests a partir do Git, em vez de `kubectl
   apply` manual.
7. **Tailscale**: use o **Tailscale Kubernetes Operator** (`Connector`
   para a LAN, `ProxyGroup`/annotations por serviço para Funnel/Serve),
   substituindo os 3 sidecars e o container `tailscale` principal.

## Segurança: boas práticas para o cluster

Esta migração é uma oportunidade de subir o nível de segurança em
relação ao Docker Compose atual, não só replicá-lo. Trate os itens
abaixo como requisitos, não sugestões opcionais:

- **Pod Security Admission em modo `restricted`** em todos os
  namespaces, com exceção explícita e documentada só para os workloads
  que realmente precisam de privilégio (Suricata, ESPHome, Kali).
- **`runAsNonRoot: true`, `readOnlyRootFilesystem: true` e `cap_drop:
  [ALL]` por padrão** em todo Pod, adicionando de volta só a capability
  estritamente necessária — mesma disciplina que o compose atual já
  aplica em parte (`cap_drop: ALL` em vários serviços), agora sem
  exceção.
- **RBAC de menor privilégio**: um `ServiceAccount` dedicado por
  workload, `automountServiceAccountToken: false` por padrão, e nenhum
  Pod usando o `default` ServiceAccount do namespace.
- **`NetworkPolicy` default-deny** (ingress e egress) em cada
  namespace, com allow-lists explícitas — não confie em isolamento
  implícito de namespace.
- **Nenhum image tag flutuante** (`latest`, `stable`, `rolling`) —
  fixe todas as imagens por digest sha256. Hoje só o Frigate faz isso;
  use a migração para estender essa prática a Suricata, CrowdSec,
  Tailscale, Kali e Mumble, que ainda usam tags flutuantes no compose.
- **Scan de imagem bloqueante de verdade**: o CI atual tem
  `image-scan` com `continue-on-error: true` (decisão documentada em
  commit anterior, aceitando CVEs de imagens de terceiros). Ao migrar,
  reavalie isso — pelo menos gate CVEs `CRITICAL` com CVE conhecido e
  corrigível (`--ignore-unfixed` já filtra o que não tem correção).
- **etcd encryption at rest** habilitado desde o início do cluster —
  não é algo que se liga depois sem downtime.
- **Backup do estado do cluster**: Velero (ou equivalente) para PVCs +
  recursos do cluster. Hoje não existe backup automatizado dos
  volumes (`../data/*`); não repita essa lacuna no k8s.
- **Runtime security**: considere Falco como equivalente, em nível de
  kernel/container, ao papel que Suricata/CrowdSec já cumprem na rede
  — alerta de comportamento anômalo dentro dos pods (spawn de shell
  inesperado, escrita em binário, etc.).
- **Admission policies** (Kyverno ou OPA/Gatekeeper) para impedir, via
  política, que qualquer Pod novo suba privilegiado ou sem
  `resources.limits` — transforma as regras acima de "boa prática" em
  "impossível de violar por acidente".
- **CIS Kubernetes Benchmark** (`kube-bench`) rodando no CI ou como Job
  periódico no cluster.
- **API server do k8s não deve ficar acessível na internet** — se for
  administrar remotamente, coloque atrás do Tailscale, no mesmo
  espírito de "zero exposição pública" que o resto do projeto já segue.
- **CrowdSec com bouncer real dentro do cluster**
  (`crowdsec-bouncer-traefik-plugin` como `Middleware`), para que o
  bloqueio não dependa só do roteador OpenWrt externo — hoje, se esse
  roteador sair do ar ou for reconfigurado, o IDS perde a capacidade de
  agir sem que nada avise.
- **Rotação da chave age do SOPS** documentada com um cadência
  definida (ex.: anual), com plano de re-encriptação de
  `sops-secrets.yaml` testado antes de precisar dele de verdade.

## Desafios específicos deste stack (resolver com cuidado, não improvisar)

- **Suricata precisa de acesso bruto à rede** (AF_PACKET em `eno1` +
  `br-homelab`). Não roda em pod comum: ou `DaemonSet` com
  `hostNetwork: true` + `NET_RAW`/`NET_ADMIN`, ou aceitar que ele só
  monitora o CNI interno e perde visibilidade da rede física — **decida
  isso explicitamente e documente a escolha**.
- **ESPHome usa `network_mode: host`** para mDNS/discovery de ESP32 na
  LAN. Mesma limitação — `hostNetwork: true` ou perde a descoberta
  automática.
- **`kali` roda permanentemente** com privilégios de rede elevados.
  Antes de portar 1:1, questione se deveria virar `Job`/pod efêmero sob
  demanda — reduz superfície de ataque de um privilégio que fica
  ocioso na maior parte do tempo.
- **MariaDB é o banco central de 5 aplicações**. Um `StatefulSet` único
  replica a topologia atual; avalie se compensa continuar centralizado.
- **`docker.sock` montado no Traefik** não existe em k8s — todo o
  `traefik/dynamic.yml` precisa virar `IngressRoute` + `Middleware`.
- **Prometheus usa nomes de container fixos** nos scrape targets —
  trocar por `kubernetes_sd_configs`.
- **A chave TLS antiga (`traefik/certs/ha1.key`) foi removida por
  estar comprometida** (esteve commitada em texto puro). Gere um
  certificado novo do zero — nunca reaproveite nada do `traefik/certs/`
  antigo.

## Ideias de melhoria (oportunidades para aproveitar durante a migração)

Coisas que já eram limitação do setup em Docker Compose e que vale
corrigir agora, já que o stack inteiro está sendo reescrito:

- **Observabilidade de logs**: hoje só existe Prometheus + Grafana
  (métricas), sem stack de logs centralizados nem Alertmanager. Adicionar
  Loki (+ Promtail/Alloy) e Alertmanager fecha essa lacuna.
- **Resource requests além de limits**: o compose atual só define
  `deploy.resources.limits.memory`. Defina também `requests` no k8s —
  necessário para o scheduler e para QoS classes previsíveis.
- **`PodDisruptionBudget`** para os serviços críticos (Traefik,
  MariaDB, Vaultwarden), evitando indisponibilidade em manutenções do
  nó.
- **Gitleaks e validação de manifests no CI** já existem/serão
  adaptados — aproveite para também rodar `kube-bench`/`kyverno test`
  como parte do pipeline, não só depois do deploy.
- **Documentar um runbook de disaster recovery** — hoje não existe um
  plano escrito de restauração; cluster single-node é ponto único de
  falha, então backup (Velero) sem um runbook testado não serve de
  muito na hora real.
- **Revisitar SSO/OIDC** com os aprendizados da tentativa anterior com
  Authentik (removida do histórico por complexidade) — se retomar,
  considerar algo mais leve antes de reintroduzir um IdP completo.

## Passo a passo

### Fase 0 — Preparação
- [ ] Escolher e documentar a distribuição k8s (recomendo k3s single-node)
- [ ] Provisionar o cluster com etcd encryption at rest habilitado
- [ ] Instalar: Traefik (ou usar o do k3s), Tailscale Operator, StorageClass funcional, (opcional) cert-manager

### Fase 1 — Fundação (secrets, storage, rede)
- [ ] Definir e implementar a estratégia de secrets; migrar todos os valores de `compose/sops-secrets.yaml`
- [ ] Criar PVCs equivalentes a cada `../data/<serviço>` usado hoje
- [ ] Organizar Namespaces (sugestão: `core`, `security`, `media`, `monitoring`) com Pod Security Admission `restricted`
- [ ] Criar `NetworkPolicy` default-deny + allow-lists equivalentes ao isolamento da rede `backend`

### Fase 2 — Banco de dados
- [ ] MariaDB como `StatefulSet` + PVC
- [ ] Portar `compose/database-init/*.sh` para um `Job` de inicialização (ou initContainer)
- [ ] Validar conexão das 5 apps dependentes

### Fase 3 — Serviços sem exigência de host network
- [ ] Home Assistant, Grafana, Prometheus, Forgejo, Vaultwarden, Mumble, OmniRoute+Redis, Frigate → `Deployment` + `Service` + PVC onde aplicável
- [ ] Portar `healthcheck` (docker) → `livenessProbe`/`readinessProbe`
- [ ] Definir `resources.limits` **e** `requests`
- [ ] Portar `cap_drop`/`cap_add`/`security_opt`/`no-new-privileges` → `securityContext` (`runAsNonRoot`, `readOnlyRootFilesystem`, capabilities explícitas)
- [ ] Fixar todas as imagens por digest sha256

### Fase 4 — Serviços com host network / privilégios
- [ ] Suricata: decidir DaemonSet+hostNetwork vs escopo reduzido (ver desafios)
- [ ] ESPHome: `hostNetwork: true` ou alternativa de mDNS
- [ ] Kali: decidir Job sob demanda vs Deployment permanente
- [ ] Tailscale: migrar para o Tailscale Operator

### Fase 5 — Ingress e roteamento
- [ ] Reescrever `traefik/dynamic.yml` como `IngressRoute` + `Middleware`
- [ ] Recriar os hostnames `*.home` apontando para o LoadBalancer/NodePort do Traefik
- [ ] Emitir certificado TLS novo (cert-manager ou manual) — nunca reaproveitar o antigo

### Fase 6 — Segurança e observabilidade
- [ ] Portar `acquis.yaml`, scenarios e profiles do CrowdSec
- [ ] Adicionar bouncer real dentro do cluster (`crowdsec-bouncer-traefik-plugin`)
- [ ] Recriar os scrape jobs do Prometheus com `kubernetes_sd_configs`
- [ ] Adicionar Loki + Alertmanager
- [ ] Adicionar Falco e políticas de admissão (Kyverno/OPA)

### Fase 7 — CI/CD
- [ ] Trocar validação `docker compose config` por `kubeconform`/`kustomize build` no `.github/workflows/ci.yaml`
- [ ] Ajustar `scan-ref` do trivy config-scan para os manifests k8s
- [ ] Adicionar `kube-bench`/`kyverno test` ao pipeline
- [ ] Considerar GitOps (Flux/Argo) para aplicação automática

### Fase 8 — Corte (cutover)
- [ ] Migrar dados (`mysqldump` do MariaDB atual → restore no `StatefulSet` novo)
- [ ] Rodar em paralelo por um período de validação
- [ ] Apontar DNS/roteador para o cluster novo
- [ ] Desligar os containers docker antigos
- [ ] Configurar backup (Velero) e validar um restore de teste antes de considerar a migração concluída

## Critérios de aceite
- Os 20 serviços rodando no cluster com paridade funcional
- Nenhum secret em texto puro nos manifests
- CI verde (lint + validação de manifests + scans de segurança)
- Acesso remoto via Tailscale funcionando igual (mesmos hostnames públicos via Funnel)
- Suricata e CrowdSec continuam gerando alertas/decisões, agora com bloqueio real dentro do cluster
- Backup testado com restore bem-sucedido

## O que NÃO fazer
- Não reaproveitar a chave/certificado TLS antigo (já foi comprometido e removido do compose)
- Não expor o dashboard do Traefik nem a API do k8s sem autenticação/rede restrita
- Não abrir portas novas na internet além do que já existe hoje (Tailscale Funnel)
- Não tratar Suricata/ESPHome/Kali como "só mais um Deployment" — cada um tem uma exigência de rede/privilégio que precisa de decisão explícita, não um port 1:1
- Não usar tags de imagem flutuantes nos manifests novos, mesmo que o compose atual ainda use em alguns serviços
