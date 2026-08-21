FROM python:3.12-slim

# Sin bytecode en disco y sin buffer en la salida: los registros del contenedor
# aparecen cuando ocurren, no cuando se llena el búfer.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /srv

# Primero las dependencias, para que la capa se cachee y no se reinstale en
# cada cambio de código.
COPY pyproject.toml ./
RUN pip install --no-cache-dir \
      "fastapi>=0.115" "uvicorn[standard]>=0.30" \
      "psycopg[binary]>=3.2" "argon2-cffi>=23.1"

COPY sivap ./sivap
COPY migraciones ./migraciones

# Sin privilegios: si alguien consigue ejecutar algo aquí dentro, que sea con
# los permisos mínimos.
RUN useradd --system --uid 10001 sivap && chown -R sivap /srv
USER sivap

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,sys; \
sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/salud').status==200 else 1)"

CMD ["uvicorn", "sivap.principal:app", "--host", "0.0.0.0", "--port", "8000"]
