import json
import subprocess
import sys
import time
from pathlib import Path

import boto3
import pytest

RAIZ = Path(__file__).resolve().parents[1]

# El handler se despliega solo, sin paquete que lo contenga, asi que en el zip queda en
# la raiz y se importa como "handler". Se replica esa forma de importarlo aca en vez de
# convertir src/ en un paquete, para que las pruebas ejerciten el mismo modulo que corre
# en produccion y no una variante empaquetada distinta.
sys.path.insert(0, str(RAIZ / "src" / "processor"))

ENDPOINT = "http://localhost:4566"
REGION = "us-east-1"
CREDENCIALES = {"aws_access_key_id": "test", "aws_secret_access_key": "test"}


@pytest.fixture(scope="session")
def outputs():
    # Los nombres de los recursos se leen del estado y no se reconstruyen a mano. Si
    # cambia el prefijo o el entorno, las pruebas siguen apuntando a donde corresponde.
    ejecucion = subprocess.run(
        ["terraform", f"-chdir={RAIZ / 'terraform'}", "output", "-json"],
        capture_output=True,
        text=True,
        check=False,
    )

    if ejecucion.returncode != 0:
        pytest.fail(f"no se pudieron leer los outputs de terraform: {ejecucion.stderr.strip()}")

    crudos = json.loads(ejecucion.stdout)

    if not crudos:
        pytest.fail("los outputs estan vacios: falta correr make apply antes de las pruebas")

    return {clave: valor["value"] for clave, valor in crudos.items()}


def _cliente(servicio):
    return boto3.client(servicio, endpoint_url=ENDPOINT, region_name=REGION, **CREDENCIALES)


@pytest.fixture(scope="session")
def eventos():
    return _cliente("events")


@pytest.fixture(scope="session")
def sqs():
    return _cliente("sqs")


@pytest.fixture(scope="session")
def dynamodb():
    return boto3.resource("dynamodb", endpoint_url=ENDPOINT, region_name=REGION, **CREDENCIALES)


@pytest.fixture(scope="session")
def wait_until():
    # No se usa un sleep fijo porque los tiempos varian en dos ordenes de magnitud: la
    # primera invocacion de la funcion obliga a LocalStack a descargar y arrancar la
    # imagen del runtime y puede tardar mas de un minuto, mientras que las siguientes
    # responden en menos de un segundo. Un sleep calibrado para el peor caso haria que
    # la suite entera tarde varios minutos sin necesidad; uno corto la vuelve inestable.
    def _esperar(condicion, timeout=120, intervalo=2, descripcion="la condicion"):
        limite = time.monotonic() + timeout

        while time.monotonic() < limite:
            resultado = condicion()

            if resultado:
                return resultado

            time.sleep(intervalo)

        pytest.fail(f"se agotaron {timeout}s esperando {descripcion}")

    return _esperar
