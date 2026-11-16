FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt gunicorn==23.0.0
COPY . .
EXPOSE 5000
# Solo la API: las páginas las entrega Nginx (repositorio del frontend)
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "servidor_admin:create_app()"]
