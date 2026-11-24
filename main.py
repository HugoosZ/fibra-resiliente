import argparse
import errno
import json
import os
import secrets
import subprocess
import sys
import tempfile
import webbrowser
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


RAIZ = Path(__file__).resolve().parent
SQL = RAIZ / "sql"
FRONTEND = RAIZ / "frontend"
COMPOSE = ("docker", "compose")
PSQL = (*COMPOSE, "exec", "-T", "db", "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "fibra", "-d", "fibra")


def preparar_entorno():
    if os.environ.get("POSTGRES_PASSWORD"):
        return

    try:
        with (RAIZ / ".env").open("x", encoding="utf-8") as archivo:
            archivo.write(f"POSTGRES_PASSWORD={secrets.token_hex(24)}\n")
    except FileExistsError:
        pass


def exportar_mapa():
    consulta = (SQL / "exportar_mapa.sql").read_text(encoding="utf-8")
    for marcador, archivo in (
        ("__CONSULTA_ATTR__", "calcular_attr.sql"),
        ("__CONSULTA_ATTR_POSTERIOR__", "calcular_attr_posterior.sql"),
    ):
        consulta = consulta.replace(marcador, (SQL / archivo).read_text(encoding="utf-8").strip().rstrip(";"))

    resultado = subprocess.run(
        (*PSQL, "-qAt"), cwd=RAIZ, input=consulta.encode("utf-8"), stdout=subprocess.PIPE, check=True
    )
    contenido = resultado.stdout.replace(b"\r\n", b"\n")
    datos = json.loads(contenido)
    attr = datos.get("attr", {})
    if datos.get("type") != "FeatureCollection" or any(attr.get(campo) is None for campo in ("attr_inicial", "attr_posterior")):
        raise ValueError("La exportación no incluye el grafo y ambos ATTR.")

    destino = FRONTEND / "datos" / "mapa.geojson"
    with tempfile.NamedTemporaryFile(dir=destino.parent, suffix=".tmp", delete=False) as archivo:
        temporal = Path(archivo.name)
    try:
        temporal.write_bytes(contenido)
        temporal.replace(destino)
    finally:
        temporal.unlink(missing_ok=True)

    print(f"Mapa exportado con {len(datos['features'])} elementos.", flush=True)


def servir_mapa(abrir_navegador):
    manejador = partial(SimpleHTTPRequestHandler, directory=str(FRONTEND))
    try:
        servidor = ThreadingHTTPServer(("127.0.0.1", 8000), manejador)
    except OSError as error:
        if error.errno not in (errno.EADDRINUSE, 10048):
            raise
        servidor = ThreadingHTTPServer(("127.0.0.1", 0), manejador)

    with servidor:
        url = f"http://127.0.0.1:{servidor.server_port}/"
        print(f"Visor Leaflet en {url}\nPresiona Ctrl+C para cerrar el visor.", flush=True)
        if abrir_navegador:
            webbrowser.open(url)
        servidor.serve_forever()


def main():
    argumentos = argparse.ArgumentParser(description="Carga la red de fibra, calcula los ATTR y levanta Leaflet.")
    argumentos.add_argument("--sin-navegador", action="store_true", help="Sirve el mapa sin abrir una pestaña.")
    opciones = argumentos.parse_args()

    try:
        preparar_entorno()
        subprocess.run((*COMPOSE, "up", "-d", "--wait"), cwd=RAIZ, check=True)
        subprocess.run((*PSQL, "-f", "/proyecto/main.sql"), cwd=RAIZ, check=True)
        exportar_mapa()
        servir_mapa(not opciones.sin_navegador)
    except KeyboardInterrupt:
        return 0
    except subprocess.CalledProcessError as error:
        print(f"Falló la ejecución de Docker Compose (código {error.returncode}). Revisa el mensaje anterior.", file=sys.stderr)
        return 1
    except (OSError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
