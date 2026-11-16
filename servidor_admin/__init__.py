"""Backend del panel administrativo de Numi (Flask + MySQL).

Solo expone la API JSON en /api/... que usa js/app.js del repositorio
numi-admin-frontend. Los .html, css/, js/ e img/ los entrega Nginx; para las
páginas privadas Nginx pregunta primero a /api/sesion (auth_request).
"""

from flask import Flask, redirect, request, session
from werkzeug.exceptions import HTTPException

from . import actividades, auth, inicio, instituciones, monitoreo, recursos, usuarios
from .config import Config
from .db import cerrar_db
from .utilidades import ErrorDeDatos, error

# Endpoints de la API que no piden sesión
API_PUBLICA = {"auth.login", "usuarios.registro", "logout"}


def create_app(config_extra=None):
    app = Flask(__name__, static_folder=None)
    app.config.from_object(Config)
    if config_extra:
        app.config.update(config_extra)

    app.teardown_appcontext(cerrar_db)
    for modulo in (auth, inicio, actividades, recursos, instituciones, usuarios, monitoreo):
        app.register_blueprint(modulo.bp)

    @app.before_request
    def exigir_sesion():
        if "usuario_id" in session:
            return None
        if request.path.startswith("/api/") and request.endpoint not in API_PUBLICA:
            return error("Tu sesión terminó. Vuelve a iniciar sesión.", 401)
        if request.endpoint == "recursos.archivo_subido":
            return redirect("/index.html")
        return None

    @app.errorhandler(ErrorDeDatos)
    def datos_invalidos(e):
        return error(e.mensaje, e.codigo)

    @app.errorhandler(HTTPException)
    def error_http(e):
        # La API siempre responde JSON, también en errores 404 o 405
        if request.path.startswith("/api/"):
            return error(e.description, e.code)
        return e

    @app.get("/api/sesion")
    def sesion():
        # Nginx (auth_request) pregunta aquí antes de entregar una página privada.
        # Si no hay sesión, exigir_sesion ya respondió 401.
        return "", 204

    @app.post("/api/logout")
    def logout():
        session.clear()
        return "", 204

    return app
