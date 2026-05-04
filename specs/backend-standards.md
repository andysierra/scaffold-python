# Spec: Backend Standards

Estándares de código backend para este microservicio. Todo el código que llegue a `main` debe cumplir estas reglas.

---

## Tipado

- Type hints obligatorios en toda función pública y en sus parámetros de retorno
- Prohibido usar `Any` salvo en adaptadores de infraestructura donde el tipo externo es genuinamente dinámico, y debe estar documentado con un comentario
- Pydantic v2 para todos los modelos de entrada/salida de la API y de configuración
- `mypy --strict` debe pasar sin errores en CI

---

## Estructura de módulos

- Cada módulo expone solo lo necesario — usar `__all__` para controlar la interfaz pública
- Sin imports circulares: el grafo de dependencias entre módulos debe ser un DAG
- Los imports se ordenan: stdlib → third-party → interno; separados por línea en blanco (aplicado por `ruff`)
- Prohibido importar desde `infrastructure/` en `domain/`

---

## Convenciones de código

- Nombres en `snake_case` para variables, funciones y módulos; `PascalCase` para clases; `UPPER_SNAKE_CASE` para constantes
- Funciones con más de 3 parámetros reciben un objeto (Pydantic model o dataclass), no argumentos posicionales
- Máximo 1 nivel de indentación dentro de una función de negocio — extraer métodos si se supera
- Sin comentarios que expliquen el qué; solo el porqué cuando no es obvio

---

## Naming de DTOs

- Los DTOs de la API se modelan en Pydantic v2 (`BaseModel`) con sufijo `Request` o `Response` — **prohibido** sufijo `Dto` / `DTO` (es convención Java).
- Viven en `infrastructure/entry_points/api_rest/schemas/` — un módulo por feature; nunca en `domain/`.
- El dominio expone modelos puros (`@dataclass` o `@dataclass(frozen=True)`); los routers convierten dominio ↔ schema en su frontera.
- El nombre describe la intención, no solo la entidad: `CreateProductRequest`, `ProductResponse`, `UpdateStockRequest`.
- Los `Command` / `Query` que entran al use case son **dataclasses del dominio**, no Pydantic — viven en `domain/services/` junto al use case que los consume.

---

## Mensajes del sistema (Messages Enum)

Todos los mensajes y códigos de respuesta del sistema se centralizan en un único archivo `src/domain/messages.py` con dos enums. Prohibido usar strings literales de mensajes o códigos sueltos fuera de ese archivo.

```python
from enum import StrEnum


class ResponseCode(StrEnum):
    # Genéricos
    SUCCESS               = "0200"
    INTERNAL_ERROR        = "0500"

    # Autenticación
    UNAUTHORIZED          = "1401"
    FORBIDDEN             = "1403"
    INVALID_CREDENTIALS   = "1001"

    # Entidades
    ENTITY_NOT_FOUND      = "2404"
    ENTITY_ALREADY_EXISTS = "2409"

    # Validación
    VALIDATION_ERROR      = "3400"
    MISSING_FIELD         = "3001"


class Messages(StrEnum):
    # Errores de dominio
    USER_NOT_FOUND            = "El usuario solicitado no existe"
    USER_ALREADY_EXISTS       = "Ya existe un usuario con ese identificador"
    INVALID_CREDENTIALS       = "Las credenciales proporcionadas son inválidas"

    # Logs de infraestructura
    DB_CONNECTION_ESTABLISHED = "Conexión a la base de datos establecida"
    DB_CONNECTION_FAILED      = "Error al conectar con la base de datos"
    REQUEST_RECEIVED          = "Solicitud recibida"
    REQUEST_COMPLETED         = "Solicitud completada"
```

`ResponseCode` sigue el formato `XYYY` donde `X` es la categoría (`0` genérico, `1` auth, `2` entidades, `3` validación) y `YYY` el código específico.

Ambos enums se combinan en el body de respuesta HTTP:

```json
{
  "code": "2404",
  "message": "El usuario solicitado no existe",
  "detail": {}
}
```

Reglas de uso:

- `ResponseCode` va en el campo `code` de toda respuesta — nunca un string literal
- `Messages` va en el campo `message` y en los logs — nunca un string literal
- Las constantes se agrupan por sección con comentario de bloque
- Contexto dinámico con f-string en el punto de uso: `f"{Messages.USER_NOT_FOUND} — id={user_id}"`; los enums nunca contienen placeholders
- Al agregar un nuevo error de dominio se agregan simultáneamente: la constante en `ResponseCode`, el mensaje en `Messages`, y la excepción tipada correspondiente en `domain/`

---

## Manejo de errores

- Los errores de dominio son excepciones tipadas que heredan de una base `DomainError`
- Los routers capturan `DomainError` y los traducen a respuestas HTTP con body estructurado:
  ```json
  { "error": "CÓDIGO_ERROR", "message": "descripción legible", "detail": {} }
  ```
- Prohibido retornar `500` por errores de negocio — solo por fallos inesperados de infraestructura
- Logs de error siempre con contexto: `request_id`, `user_id` si aplica, y el stack trace

---

## Mapping dominio ↔ ORM

- El modelo de dominio (`@dataclass`) y el modelo ORM (SQLAlchemy `Base`) son **dos clases distintas** y viven en lugares distintos: la entidad en `domain/models/`, el ORM en `infrastructure/driven_adapters/persistence/models/`.
- Mapping manual y explícito con métodos `to_domain()` / `from_domain()` dentro del adapter de persistencia (`<X>Repository`).
- Prohibido `Mapped[...]`, anotaciones de SQLAlchemy o cualquier import de infraestructura en la entidad de dominio.
- El adapter de salida es el **único** responsable de conocer ambos modelos y traducir entre ellos.
- Sin librerías de mapping automático cruzando capas (tipo MapStruct, o `from_attributes=True` de Pydantic apuntando a un ORM) — la traducción se escribe a mano para mantener el dominio aislado.

---

## Calidad y linting

| Herramienta | Propósito | Umbral |
|---|---|---|
| `ruff` | Linting y formato | Cero warnings |
| `mypy --strict` | Tipado estático | Cero errores |
| SonarQube | Calidad y seguridad | Quality Gate en servidor Docker |
| `pytest --cov` | Cobertura | ≥ 90% en líneas |

- Cognitive complexity ≤ 15 por función
- Sin bloques duplicados > 10 líneas
- Sin secretos hardcodeados, sin SQL por concatenación, sin `eval()`

---

## Async

- Toda función que toca I/O (DB, Redis, HTTP externo) debe ser `async def`
- Prohibido usar clientes síncronos dentro de request handlers de FastAPI
- Para operaciones CPU-intensivas usar `asyncio.run_in_executor` — nunca bloquear el event loop

---

## Configuración

- Toda configuración en una clase Pydantic `Settings` cargada desde variables de entorno
- Un único punto de entrada a la configuración (`src/config.py`) — sin leer `os.environ` disperso en el código
- Valores sensibles nunca tienen default en código — fallan rápido si no están definidos en el entorno
