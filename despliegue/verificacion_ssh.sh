#!/usr/bin/env bash
# Verificación en vivo por SSH para el video de Numi (sección 4 del enunciado).
# Uso, ya conectado por SSH a la VM:   bash ~/numi/verificacion_ssh.sh
# Cada pantalla ejecuta los comandos en vivo y espera Enter para seguir.
# No muestra contraseñas, claves ni tokens: el .env se lista con los valores tapados.

cd "$HOME/numi" || exit 1
DNS=numi-g01.northcentralus.cloudapp.azure.com
DC="sudo docker compose"
N=0
TOTAL=10

ocultar() { sed -E 's/181\.58\.[0-9]{1,3}\.[0-9]{1,3}/<ip-admin>/g'; }
pantalla() {
  N=$((N + 1)); clear
  printf '\033[1;37;46m  %02d/%02d  \033[0m \033[1;36m%s\033[0m\n' "$N" "$TOTAL" "$1"
}
paso() { printf '\n\033[1;33m# %s\033[0m\n' "$1"; }
cmd() {
  printf '\033[1;32mazureuser@vm-numi-g01\033[0m:\033[1;34m~/numi\033[0m$ %s\n' "$1"
  eval "$1" 2>&1 | ocultar
}
fin() { printf '\n\033[2m--- Enter para continuar ---\033[0m'; read -r _; }
sql() { $DC exec -T mysql sh -c "MYSQL_PWD=\"\$MYSQL_PASSWORD\" mysql --table --user=\"\$MYSQL_USER\" --database=\"\$MYSQL_DATABASE\" -e \"$1\""; }

# 1 ---------------------------------------------------------------------------
pantalla "Identidad del servidor y del usuario"
paso "¿Quién soy y en qué máquina estoy?"
cmd "whoami && id"
cmd "hostname && grep PRETTY_NAME /etc/os-release"
paso "IP privada de la VM (la pública la tiene Azure en la NIC)"
cmd "ip -4 -brief addr show eth0"
paso "Datos de la VM según el servicio de metadatos de Azure"
cmd "curl -s -H Metadata:true 'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(f\"{k:15} {d[k]}\") for k in (\"name\",\"resourceGroupName\",\"location\",\"vmSize\")]'"
fin

# 2 ---------------------------------------------------------------------------
pantalla "Archivos y código del proyecto"
cmd "ls -la ~/numi"
cmd "ls ~/numi/repos"
paso "Secretos: el .env solo lo lee azureuser (600) y aquí se ven solo los nombres"
cmd "ls -l .env"
cmd "sed -E 's/=.*/=********/' .env"
paso "Frontend (archivos estáticos) y backend (API Flask)"
cmd "ls repos/numi-admin-frontend repos/numi-docente-frontend"
cmd "ls repos/numi-admin-backend repos/numi-docente-backend"
fin

# 3 ---------------------------------------------------------------------------
pantalla "Repositorios Git (4: frontend y backend de cada panel)"
for r in numi-admin-frontend numi-admin-backend numi-docente-frontend numi-docente-backend; do
  paso "$r"
  cmd "git -C repos/$r remote get-url origin && git -C repos/$r log -1 --format='%h %ad %s' --date=short && git -C repos/$r status -sb | head -1"
done
fin

# 4 ---------------------------------------------------------------------------
pantalla "Docker y Docker Compose"
cmd "sudo systemctl is-active docker && sudo systemctl is-enabled docker"
cmd "docker --version && docker compose version"
paso "Archivo de Compose que se está usando (servicios, imágenes y puertos)"
cmd "$DC config --services"
cmd "grep -nE '^  [a-z-]+:$|image:|build:|ports:|- \"[0-9]+:[0-9]+\"|expose:' compose.yaml"
fin

# 5 ---------------------------------------------------------------------------
pantalla "Imágenes y contenedores"
cmd "sudo docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' | grep -E 'REPOSITORY|numi|mysql|nginx|certbot'"
paso "Estado de BD, backends y frontend (Nginx)"
cmd "$DC ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"
paso "Últimas líneas de los backends (Gunicorn)"
cmd "$DC logs --tail 3 admin-backend docente-backend"
fin

# 6 ---------------------------------------------------------------------------
pantalla "Base de datos y almacenamiento persistente"
paso "Conexión a MySQL con el usuario de la app (la clave sale del .env, no se muestra)"
cmd "sql 'SELECT DATABASE() AS base, CURRENT_USER() AS usuario, VERSION() AS version;'"
cmd "sql 'SELECT COUNT(*) AS tablas FROM information_schema.tables WHERE table_schema = DATABASE();'"
cmd "sql 'SELECT rol, estado, COUNT(*) AS cuentas FROM usuarios GROUP BY rol, estado;'"
paso "Volúmenes: los datos sobreviven aunque se borren los contenedores"
cmd "sudo docker volume ls | grep numi"
cmd "sudo docker volume inspect numi_mysql_data --format 'numi_mysql_data -> {{.Mountpoint}}'"
cmd "df -h / | tail -1"
fin

# 7 ---------------------------------------------------------------------------
pantalla "Servidor web y proxy inverso (Nginx + HTTPS)"
cmd "$DC exec -T nginx nginx -t"
paso "Qué escucha, qué entrega y a dónde reenvía"
cmd "grep -nE 'listen|root |location|proxy_pass|auth_request|return 30' nginx/conf.d/numi.conf"
paso "Certificado de Let's Encrypt (solo la parte pública)"
cmd "echo | openssl s_client -connect $DNS:443 -servername $DNS 2>/dev/null | openssl x509 -noout -subject -issuer -enddate"
fin

# 8 ---------------------------------------------------------------------------
pantalla "Comunicación interna entre servicios"
paso "Puertos abiertos en la VM: solo SSH y los de Nginx. MySQL y los backends no se publican"
cmd "sudo ss -tlnp | awk 'NR==1 || /:(22|80|443|8080|8443|3306|5000|5001) /' | awk '{print \$1, \$4, \$6}' | column -t"
paso "Red interna de Docker"
cmd "sudo docker network inspect numi_default --format '{{range .Containers}}{{.Name}}  {{.IPv4Address}}{{println}}{{end}}'"
paso "Nginx -> backends por nombre de servicio"
cmd "$DC exec -T nginx wget -S -qO- http://admin-backend:5000/api/sesion 2>&1 | head -1"
cmd "$DC exec -T nginx wget -S -qO- http://docente-backend:5001/api/sesion 2>&1 | head -1"
paso "Backend -> MySQL por la red interna"
cmd "$DC exec -T admin-backend python -c \"import socket; socket.create_connection(('mysql', 3306), 3); print('admin-backend -> mysql:3306 OK')\""
cmd "$DC exec -T docente-backend python -c \"import socket; socket.create_connection(('mysql', 3306), 3); print('docente-backend -> mysql:3306 OK')\""
fin

# 9 ---------------------------------------------------------------------------
pantalla "Respuestas HTTP por el nombre DNS"
paso "HTTP redirige a HTTPS"
cmd "curl -sI http://$DNS/ | head -3"
cmd "curl -sI http://$DNS:8080/ | grep -iE '^HTTP|^location'"
paso "Panel administrativo (443)"
cmd "curl -s -o /dev/null -w '%{http_code}  /index.html  (%{content_type})\n' https://$DNS/index.html"
cmd "curl -s -o /dev/null -w '%{http_code}  /inicio.html sin sesión -> %{redirect_url}\n' https://$DNS/inicio.html"
cmd "curl -s -w '\n%{http_code}  /api/inicio sin sesión\n' https://$DNS/api/inicio"
paso "Panel docente (8443)"
cmd "curl -s -o /dev/null -w '%{http_code}  :8443/index.html\n' https://$DNS:8443/index.html"
cmd "curl -s -w '\n%{http_code}  :8443/api/me sin sesión\n' https://$DNS:8443/api/me"
fin

# 10 --------------------------------------------------------------------------
pantalla "Lo que NO está expuesto"
paso "Desde afuera solo responden 80/443/8080/8443; MySQL (3306) y los backends (5000/5001) no"
for p in 3306 5000 5001; do
  cmd "timeout 4 bash -c '</dev/tcp/$DNS/$p' && echo 'puerto $p ABIERTO' || echo 'puerto $p cerrado desde afuera'"
done
paso "SSH: solo con llave (sin contraseña) y el NSG solo lo deja pasar desde la IP del administrador"
cmd "sudo sshd -T | grep -E '^(passwordauthentication|pubkeyauthentication|permitrootlogin) '"
paso "Las rutas internas de Nginx no se pueden pedir desde el navegador"
cmd "curl -s -o /dev/null -w '%{http_code}  /_sesion\n' https://$DNS/_sesion"
cmd "curl -s -o /dev/null -w '%{http_code}  /app.py\n' https://$DNS/app.py"
printf '\n\033[1;32mFin de la verificación.\033[0m\n'
