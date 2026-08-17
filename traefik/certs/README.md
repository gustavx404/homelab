# traefik/certs/

Este diretório precisa conter `ha1.key` e `ha1.crt` em runtime (montados em `/certs` no
container do Traefik), mas os arquivos **não são versionados** (ver `.gitignore`).

Um par de chave/certificado real ficou commitado neste repositório (ver
`git log -- traefik/certs/ha1.key` para o histórico) e deve ser considerado
comprometido: gere um novo e nunca reutilize o antigo.

Para gerar um certificado autoassinado local:

```sh
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout traefik/certs/ha1.key \
  -out traefik/certs/ha1.crt \
  -subj "/CN=ha1.<seu-tailnet>.ts.net"
```
