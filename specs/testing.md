# Spec: Testing

Estrategia de testing del microservicio. Se prioriza **velocidad de feedback** y **cobertura de la lógica que importa** sobre tests exhaustivos de plumbing.

---

## Alcance — solo tests unitarios

Solo tests unitarios con `pytest` + `pytest-mock` + `unittest.mock.AsyncMock`. **Sin I/O real**: sin DB, sin HTTP, sin Redis. La lógica que importa (reglas de negocio, invariantes, transiciones de estado, validación de tokens) vive en el dominio puro y se cubre con mocks.

Tests de integración (DB real, HTTP real, TestClient de FastAPI) **no están en scope** del scaffold base; se agregan como evolutivo si una feature concreta los justifica, con marker `@pytest.mark.integration` y servicio compose separado.

---

## Estructura

`tests/` espeja la estructura del código testeado:

```
tests/
  unit/
    domain/
      conftest.py            # fixtures compartidas (entidades de muestra)
      models/
        test_<value_object>.py
        test_<entity>.py
      services/
        test_<use_case>.py
    security/                # solo si hay seguridad
      test_jwt_validator.py
      test_principal.py
```

---

## Naming

Cada test sigue el patrón **`test_dado<Contexto>_cuando<Accion>_entonces<ResultadoEsperado>`** con segmentos en PascalCase:

```python
def test_dadoSubscriptionPending_cuandoSeActiva_entoncesQuedaActiveConFechas(...): ...
```

Si el test no se puede expresar en ese formato, probablemente está mal pensado (testea más de una cosa, o no tiene precondición clara).

---

## Qué se testea / qué NO

| Capa | ¿Unit test? | Cómo |
|---|---|---|
| `domain/models/` (entidades + VOs) | ✅ | Construir directo, ejercitar métodos, asserts |
| `domain/services/` (use cases) | ✅ | Mockear gateways con `AsyncMock(spec=...)`, ejercitar `execute()` |
| `entry_points/api_rest/security/jwt_validator.py` y `principal.py` | ✅ | Pure crypto + lógica de claims; generar tokens con `jwt.encode` |
| `driven_adapters/persistence/**` | ❌ | Requiere DB real → integración |
| `driven_adapters/clients/**` | ❌ | Requiere HTTP real → integración |
| `driven_adapters/config/**` | ❌ | Wiring de fábricas; cero lógica testeable |
| `entry_points/api_rest/routers/**` | ❌ | Requiere TestClient → integración |
| `entry_points/api_rest/middleware.py` | ❌ | Requiere TestClient → integración |
| `entry_points/api_rest/error_handlers.py` | ❌ | Requiere TestClient → integración |
| `entry_points/api_rest/dependencies.py` | ❌ | FastAPI Depends; wiring puro |
| `src/main.py`, `src/config.py` | ❌ | Wiring / construcción de app |

Si lógica de coordinación crítica termina en un router o middleware, **refactorizá** a un service del dominio. Los routers solo serializan/deserializan.

---

## Mocking — patrones

- **Gateways**: `AsyncMock(spec=SubscriptionGateway)` — el `spec` previene typos en nombres de métodos y captura cambios de contrato.
- **Tiempo**: la entidad recibe `now` como parámetro de método (`activate(now, period_end)`). El test pasa un `datetime` literal. Evitá `freezegun` salvo última opción.
- **UUIDs**: dejar que `uuid4()` genere; nunca hardcodear UUIDs salvo en assertions específicas que comparan identidad.
- **Settings en tests**: instanciar `Settings(...)` con kwargs explícitos; no leer `.env` ni env vars de la máquina del dev.

---

## Async

`pytest-asyncio` con `asyncio_mode = "auto"` en `pyproject.toml`. Los tests async no requieren `@pytest.mark.asyncio`.

---

## Cobertura

- **Umbral: ≥ 90% líneas y branches** sobre el código en scope (dominio + seguridad pura).
- Reportes generados por `pytest`: `term-missing` (consola) **y** `xml` (para SonarQube).
- **Exclusiones** de cobertura — código que no se testea unitariamente por diseño:
  - `src/main.py`
  - `src/config.py`
  - `src/infrastructure/driven_adapters/persistence/**`
  - `src/infrastructure/driven_adapters/clients/**`
  - `src/infrastructure/driven_adapters/config/**`
  - `src/infrastructure/entry_points/api_rest/routers/**`
  - `src/infrastructure/entry_points/api_rest/middleware.py`
  - `src/infrastructure/entry_points/api_rest/error_handlers.py`
  - `src/infrastructure/entry_points/api_rest/dependencies.py`
  - `src/infrastructure/entry_points/api_rest/security/dependencies.py`

Las mismas exclusiones se replican en `sonar-project.properties` para que la métrica del Quality Gate sea consistente con la realidad del scaffold.

---

## Ejecución

Local sin instalación de Python en la máquina del dev:

```bash
docker compose --profile dev run --rm test
```

Esto genera `coverage.xml` que después consume:

```bash
SONAR_TOKEN=<token> docker compose --profile dev run --rm sonar
```

---

## Lo que NO está en scope (evolutivos)

- Tests de integración con Postgres real + Alembic
- Tests de integración HTTP con `TestClient` de FastAPI
- Mocks de httpx con `respx`
- Property-based testing (`hypothesis`)
- Mutation testing
- Performance / load testing

Cuando una de estas piezas se necesite, se agrega:
1. Nuevas dependencias dev
2. Marker `@pytest.mark.integration` (registrado en `pyproject.toml`)
3. Servicio compose separado o variante de la suite
4. Sección adicional en este spec
