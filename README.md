# Numi · Panel administrativo · Backend

API del panel administrativo de **Numi** (Python 3.12, Flask 3, MySQL 8 con PyMySQL). También tiene el
esquema de la base de datos que comparten los dos paneles y la configuración del despliegue en Azure.

- **Frontend:** [numi-admin-frontend](https://github.com/luism7p7/numi-admin-frontend)
- **Panel docente:** [numi-docente-frontend](https://github.com/luism7p7/numi-docente-frontend) · [numi-docente-backend](https://github.com/luism7p7/numi-docente-backend)
- **En producción:** https://numi-g01.northcentralus.cloudapp.azure.com

## Estructura

```
├── servidor_admin/     # blueprints: auth, inicio, actividades, recursos, instituciones, usuarios, monitoreo
├── database/           # schema.sql (16 tablas), init_db.py (datos demo), importar_recursos_app.py
├── despliegue/         # compose.yaml, nginx/numi.conf e instalar.sh para la VM de Azure
├── tests/              # pytest
├── app.py              # python app.py -> http://localhost:5000 (solo la API)
├── Dockerfile          # imagen con Gunicorn
└── .env.example
```

## Despliegue en Azure

La VM `vm-numi-g01` (Ubuntu 24.04) corre todo con Docker Compose (`despliegue/compose.yaml`):

| Servicio | Qué es | Puertos |
|----------|--------|---------|
| `mysql` | MySQL 8.4 con volumen `numi_mysql_data` | ninguno publicado |
| `admin-backend` | Este repositorio (Gunicorn :5000) | solo red interna |
| `docente-backend` | numi-docente-backend (Gunicorn :5001) | solo red interna |
| `nginx` | Entrega los dos frontends y hace de proxy inverso, con HTTPS de Let's Encrypt | 80, 443, 8080, 8443 |

- Panel administrativo: https://numi-g01.northcentralus.cloudapp.azure.com
- Panel docente: https://numi-g01.northcentralus.cloudapp.azure.com:8443
- 80 y 8080 solo redirigen a HTTPS. SSH (22) solo se permite desde la IP del administrador (regla del NSG).

```bash
# En la VM, con ~/numi/.env creado (chmod 600)
git clone https://github.com/luism7p7/numi-admin-backend.git ~/numi/repos/numi-admin-backend
bash ~/numi/repos/numi-admin-backend/despliegue/instalar.sh
```

El script clona o actualiza los 4 repositorios, saca el certificado, copia la configuración de Nginx, levanta
los contenedores y deja programada la renovación del certificado.

## Probarlo en local (sin Docker)

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env        # escribe tu DB_PASSWORD
python database/init_db.py         # crea la base numi con datos de ejemplo
python app.py                      # API en http://localhost:5000/api/...
```

Cuenta de ejemplo: `cvelez@medellin.gov.co` (Administrador). La contraseña demo está en `database/init_db.py`.

## API

| Método | URL | Qué hace |
|--------|-----|----------|
| GET | `/api/sesion` | 204 si hay sesión, 401 si no (lo usa Nginx con auth_request) |
| POST | `/api/logout` | Cierra la sesión |


| Pantalla | Endpoints |
|----------|-----------|
| Login / Crear usuario | `POST /api/login`, `POST /api/registro` |
| Inicio | `GET /api/inicio` |
| Actividades, detalle, borradores | `GET /api/actividades`, `GET/PUT/DELETE /api/actividades/<id>` |
| Constructor | `POST /api/actividades` (Publicada o Borrador), `GET /api/recursos` |
| Historial | `GET /api/historial` |
| Recursos | `GET /api/recursos`, `POST /api/recursos` (subir PNG/JPG/MP3) |
| Instituciones | `GET/POST /api/instituciones`, `GET /api/instituciones/<id>` |
| Usuarios | `GET/POST /api/usuarios`, `PUT /api/usuarios/<id>`, `PATCH /api/usuarios/<id>/estado`, `POST /api/usuarios/importar` |
| Monitoreo técnico | `GET /api/monitoreo`, `POST /api/informes`, `GET /api/informes/<id>/descargar` |
## Tipos de actividad que se arman en el panel

El constructor crea actividades de seis tipos. La app las juega con una plantilla de su tipo, sin
programar pantallas nuevas (el formato de cada contenido está en `servidor_admin/plantillas.py`):

| Tipo | El niño... | Contenido |
|------|-----------|-----------|
| Selección múltiple | elige la respuesta correcta | `preguntas` |
| Comprensión auditiva | escucha un audio y elige la respuesta | `preguntas` (cada una con audio) |
| Arrastrar | arrastra cada elemento al grupo al que pertenece | `grupos` + `elementos` |
| Arrastrar y soltar | arrastra cada elemento hasta su pareja | `parejas` |
| Ordenar sílabas | ordena las sílabas de una palabra | `palabras` |
| Memory match | encuentra los pares de cartas | `pares` |

Un borrador puede estar incompleto; para publicar, el contenido se valida completo.
## Pruebas

```powershell
python -m pytest
```

Usan una base aparte (`numi_test`) que se crea de nuevo en cada archivo de pruebas.

## Equipo

- Luis Miguel Muñoz Rendón
- Alexander Mejía Ospina
- Santiago Mayorga Hueso
- Santiago Rodríguez Jiménez

Proyecto Numi · Universidad Cooperativa de Colombia, sede Medellín.
