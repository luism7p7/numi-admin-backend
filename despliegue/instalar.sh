#!/usr/bin/env bash
# Despliega (o actualiza) Numi en la VM de Azure a partir de los 4 repositorios de GitHub.
# Uso, en la VM como azureuser:   bash ~/numi/repos/numi-admin-backend/despliegue/instalar.sh
# Requisitos: Docker + Compose, ~/numi/.env (chmod 600), volúmenes numi_mysql_data y numi_uploads,
# y el puerto 80 abierto en el NSG para que Let's Encrypt valide el dominio.
set -euo pipefail

DNS=numi-g01.northcentralus.cloudapp.azure.com
BASE="$HOME/numi"
GITHUB=https://github.com/luism7p7
REPOS="numi-admin-frontend numi-admin-backend numi-docente-frontend numi-docente-backend"

cd "$BASE"
test -f .env || { echo "Falta $BASE/.env"; exit 1; }
chmod 600 .env
mkdir -p repos certbot/conf certbot/www nginx/conf.d

echo "== 1. Repositorios"
for r in $REPOS; do
  if [ -d "repos/$r/.git" ]; then git -C "repos/$r" pull --ff-only; else git clone "$GITHUB/$r.git" "repos/$r"; fi
done

echo "== 2. Volúmenes (los datos de MySQL y los archivos subidos no se pierden)"
docker volume create numi_mysql_data >/dev/null
docker volume create numi_uploads >/dev/null

echo "== 3. Certificado HTTPS (Let's Encrypt)"
if [ ! -f "certbot/conf/live/$DNS/fullchain.pem" ]; then
  # certbot necesita el puerto 80 libre un momento
  docker compose stop nginx 2>/dev/null || true
  docker run --rm -p 80:80 -v "$BASE/certbot/conf:/etc/letsencrypt" certbot/certbot \
    certonly --standalone -d "$DNS" --agree-tos --register-unsafely-without-email --non-interactive
fi

echo "== 4. Configuración de Compose y Nginx"
D=repos/numi-admin-backend/despliegue
[ -f compose.yaml ] && cp compose.yaml "compose.yaml.antes-$(date +%Y%m%d-%H%M%S).bak"
cp "$D/compose.yaml" compose.yaml
rm -f nginx/conf.d/*.conf
cp "$D/nginx/numi.conf" "$D/nginx/proxy_headers.inc" nginx/conf.d/
cp "$D/verificacion_ssh.sh" "$BASE/verificacion_ssh.sh"

echo "== 5. Contenedores"
docker compose up -d --build --remove-orphans
sleep 5
docker compose exec -T nginx nginx -t
docker compose exec -T nginx nginx -s reload

echo "== 6. Renovación automática del certificado (todos los días a las 03:15)"
LINEA="15 3 * * * cd $BASE && docker compose run --rm certbot renew --webroot -w /var/www/certbot --quiet && docker compose exec -T nginx nginx -s reload"
{ crontab -l 2>/dev/null | grep -v 'certbot renew' || true; echo "$LINEA"; } | crontab -

docker compose ps
echo "Listo: https://$DNS  (administrativo)   https://$DNS:8443  (docente)"
