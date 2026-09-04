import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]

# El handler se despliega solo, sin paquete que lo contenga, asi que en el zip queda en
# la raiz y se importa como "handler". Se replica esa forma de importarlo aca en vez de
# convertir src/ en un paquete, para que las pruebas ejerciten el mismo modulo que corre
# en produccion y no una variante empaquetada distinta.
sys.path.insert(0, str(RAIZ / "src" / "processor"))
