"""Cria providers OAuth2/OIDC + applications no Authentik (idempotente).

Roda DENTRO do container authentik-server via `ak shell` (ver authentik-oidc-setup.sh).
Imprime os Client ID/Secret gerados para copiar ao sops.
Provider com redirect_uris e scopes por app; validez do access token 10min
(evita colisao com a janela de 5min dos clientes Bitwarden/Immich).
"""

from datetime import timedelta

from authentik.core.models import Application
from authentik.crypto.models import CertificateKeyPair
from authentik.flows.models import Flow
from authentik.providers.oauth2.models import (
    OAuth2Provider,
    RedirectURI,
    RedirectURIMatchingMode,
    RedirectURIType,
    ScopeMapping,
)

AUTH_FLOW_SLUG = "default-provider-authorization-explicit-consent"
INVALIDATION_FLOW_SLUG = "default-provider-invalidation-flow"
SIGNING_KEY_NAME = "authentik Self-signed Certificate"
SCOPE_PREFIX = "goauthentik.io/providers/oauth2/scope-"

PROVIDERS = [
    {
        "name": "Immich",
        "slug": "immich",
        "launch": "https://photos.home",
        "redirect_uris": [
            "https://photos.home/auth/login",
            "https://photos.home/user-settings",
            "app.immich:///oauth-callback",
        ],
        "scopes": ["openid", "profile", "email"],
    },
    {
        "name": "Vaultwarden",
        "slug": "vaultwarden",
        "launch": "https://vault.home",
        "redirect_uris": ["https://vault.home/identity/connect/oidc-signin"],
        "scopes": ["openid", "profile", "email", "offline_access"],
    },
]


def main() -> None:
    auth_flow = Flow.objects.get(slug=AUTH_FLOW_SLUG)
    invalidation_flow = Flow.objects.get(slug=INVALIDATION_FLOW_SLUG)
    signing_key = CertificateKeyPair.objects.filter(name=SIGNING_KEY_NAME).first()
    if signing_key is None:
        raise RuntimeError(f"signing key '{SIGNING_KEY_NAME}' nao encontrada")

    scopes: dict[str, ScopeMapping] = {}
    for m in ScopeMapping.objects.filter(managed__startswith=SCOPE_PREFIX):
        scopes[m.managed.removeprefix(SCOPE_PREFIX)] = m

    for spec in PROVIDERS:
        if OAuth2Provider.objects.filter(name=spec["name"]).exists():
            print(f"SKIP {spec['name']}: provider ja existe")
            continue
        provider = OAuth2Provider(
            name=spec["name"],
            authorization_flow=auth_flow,
            invalidation_flow=invalidation_flow,
            signing_key=signing_key,
            client_type="confidential",
            grant_types=["authorization_code"],
            redirect_uris=[
                RedirectURI(
                    matching_mode=RedirectURIMatchingMode.STRICT,
                    url=url,
                    redirect_uri_type=RedirectURIType.AUTHORIZATION,
                )
                for url in spec["redirect_uris"]
            ],
            access_code_validity=timedelta(seconds=600),
            access_token_validity=timedelta(seconds=600),
            sub_mode="hashed_user_id",
            issuer_mode="global",
        )
        provider.save()
        provider.property_mappings.set([scopes[s] for s in spec["scopes"] if s in scopes])
        Application.objects.create(
            name=spec["name"],
            slug=spec["slug"],
            provider=provider,
            meta_launch_url=spec["launch"],
        )
        print(f"CREATED {spec['name']}: client_id={provider.client_id} client_secret={provider.client_secret}")


# Nota: rodado via `ak shell -c "exec(...)"` — __name__ NAO e "__main__",
# entao main() e chamado diretamente.
main()
