# Spec: Arquitectura Hexagonal

Referencia de arquitectura para este microservicio. Basada en el scaffold de Bancolombia (Java/Spring WebFlux), adaptada a Python/FastAPI.

---

## Concepto

La arquitectura hexagonal (Ports & Adapters) organiza el código en torno al dominio de negocio. El dominio es el núcleo y no conoce nada del mundo exterior — ni bases de datos, ni frameworks, ni HTTP. Todo lo externo se conecta a través de interfaces llamadas **gateways**.

La regla fundamental: **las dependencias solo apuntan hacia adentro**.

```
infrastructure  →  domain
                ↑
           (nunca al revés)
```

---

## Estructura de carpetas

```
src/
  domain/
    model/
      product.py          ← entidad con reglas de negocio
      price.py            ← value object (inmutable, con invariante)
      sku.py              ← value object (inmutable, con invariante)
      exceptions.py       ← errores de dominio tipados
      gateways/
        product_gateway.py ← interfaz abstracta (puerto de salida)
    usecase/
      create_product.py   ← caso de uso: orquesta modelo + gateway
      get_product.py
      list_products.py
      update_stock.py
      deactivate_product.py
  infrastructure/
    driven_adapters/      ← adaptadores de salida (implementan gateways)
      db/
        base.py           ← DeclarativeBase de SQLAlchemy
        session.py        ← engine y factory de sesiones async
        models/
          product_model.py ← ORM model (detalle de infraestructura)
      product_repository.py ← implementa ProductGateway con SQLAlchemy
    entry_points/         ← adaptadores de entrada (HTTP, eventos, etc.)
      api_rest/
        routers/
          health.py       ← GET /health, GET /ready
          products.py     ← endpoints REST de productos
        dependencies.py   ← inyección de dependencias con FastAPI Depends
        error_handlers.py ← convierte DomainError → JSON estructurado
  config.py               ← Settings Pydantic desde variables de entorno
  main.py                 ← registro de routers, lifespan, exception handlers
```

---

## Capas y responsabilidades

### `domain/model/`

Contiene los objetos de negocio puros. **Cero imports de frameworks o infraestructura.**

- **Entidades**: objetos con identidad (`id: UUID`). Contienen comportamiento de negocio (`update_stock`, `deactivate`).
- **Value objects**: inmutables (`@dataclass(frozen=True)`). Encapsulan una regla de validación. Si el valor es inválido, lanzan `ValidationError` en `__post_init__`.
- **Exceptions**: heredan de `DomainError`. Cada excepción conoce su `code` (de `ResponseCode`), su `message` (de `Messages`) y su `http_status`.
- **Gateways**: interfaces abstractas (`ABC`) que definen qué necesita el dominio del exterior. El dominio habla en términos de dominio, nunca de SQL ni HTTP.

```python
# Correcto: el gateway habla en términos de dominio
class ProductGateway(ABC):
    async def get_by_id(self, product_id: UUID) -> Product | None: ...

# Incorrecto: el dominio no debe saber que existe SQLAlchemy
class ProductGateway(ABC):
    async def get_by_id(self, session: AsyncSession, id: UUID): ...
```

### `domain/usecase/`

Casos de uso: orquestan el modelo y los gateways para cumplir una intención de negocio.

- Reciben sus dependencias (gateways) por **inyección en el constructor** — nunca las instancian.
- Un caso de uso = una clase con un método `execute(command | query)`.
- Contienen la lógica de coordinación: validar unicidad, invocar comportamiento de la entidad, persistir.
- No importan nada de `infrastructure/`.

```python
class CreateProductUseCase:
    def __init__(self, gateway: ProductGateway) -> None:  # ← recibe interfaz, no implementación
        self._gateway = gateway

    async def execute(self, command: CreateProductCommand) -> Product:
        ...
```

### `infrastructure/driven_adapters/`

Adaptadores de **salida**: implementan los gateways definidos en el dominio.

- `SQLAlchemyProductRepository` implementa `ProductGateway`.
- Responsable de traducir entre el modelo de dominio (`Product`) y el modelo ORM (`ProductModel`).
- El modelo ORM (`ProductModel`) es un detalle de infraestructura — el dominio nunca lo ve.
- Aquí viven: repositorios, clientes HTTP externos, clientes Redis, productores de mensajes.

### `infrastructure/entry_points/`

Adaptadores de **entrada**: reciben requests del exterior y los traducen a llamadas a casos de uso.

- Los routers FastAPI solo hacen: deserializar request → construir command/query → invocar use case → serializar response.
- **Sin lógica de negocio** en los routers.
- `dependencies.py` construye y conecta el grafo de dependencias usando `Depends` de FastAPI.
- `error_handlers.py` captura `DomainError` y lo convierte al formato estándar de respuesta.

---

## El patrón Gateway

El gateway es la pieza clave que permite que el dominio sea independiente de la infraestructura.

```
domain/model/gateways/product_gateway.py   ← define el contrato (ABC)
infrastructure/driven_adapters/product_repository.py ← implementa el contrato
```

El caso de uso depende únicamente de la interfaz abstracta. En producción recibe la implementación SQLAlchemy; en tests recibe un `AsyncMock`. El caso de uso no cambia en ninguno de los dos contextos.

```python
# En producción (via FastAPI Depends)
CreateProductUseCase(SQLAlchemyProductRepository(session))

# En tests (unitarios)
CreateProductUseCase(AsyncMock())
```

---

## Reglas de importación

| Desde | Puede importar de | No puede importar de |
|---|---|---|
| `domain/model/` | `domain/messages.py` | `domain/usecase/`, `infrastructure/` |
| `domain/usecase/` | `domain/model/` | `infrastructure/` |
| `infrastructure/driven_adapters/` | `domain/model/`, `domain/usecase/` | `infrastructure/entry_points/` |
| `infrastructure/entry_points/` | `domain/usecase/`, `domain/model/`, `driven_adapters/` | — |

---

## Puertos de entrada (decisión de diseño)

En el estilo Bancolombia clásico (Java/Spring), los casos de uso se modelan como **interfaces explícitas** en `port/in/`, implementadas por una clase service. El controller depende de la interfaz, no de la implementación.

```
domain/
  port/in/FirmaDesatendidaUseCase.java     ← interfaz
  service/FirmaDesatendidaService.java     ← implementación
```

En Python idiomático **se omite** esta capa: los casos de uso son clases concretas que reciben sus gateways por constructor. Los tests mockean los gateways directamente, sin necesitar otra abstracción.

```python
# Suficiente — clase concreta
class CreateProductUseCase:
    def __init__(self, gateway: ProductGateway) -> None:
        self._gateway = gateway

    async def execute(self, command: CreateProductCommand) -> Product: ...
```

**Cuándo activar puertos de entrada en Python:**

- Vas a tener **múltiples implementaciones** del mismo caso de uso (poco común).
- Necesitas que el adapter de entrada dependa solo de una abstracción explícita (acoplamiento al contrato, no a la clase concreta).
- El equipo viene de Java y quiere paridad estructural exacta con el scaffold Bancolombia.

Si los activas, viven en `domain/usecase/ports/` y se nombran sin prefijo `I`:

```
domain/usecase/
  ports/
    create_product_use_case.py   ← class CreateProductUseCase(ABC)
  create_product.py              ← class CreateProductService(CreateProductUseCase)
```

Por defecto, este scaffold **no** los usa.

---

## Equivalencias Java/Spring → Python

Esta arquitectura tiene su origen en el scaffold de Bancolombia (Java/Spring). Las equivalencias técnicas para aplicarla idiomáticamente en Python son:

| Java/Spring | Python idiomático |
|---|---|
| `interface IFooPort` | `class FooGateway(ABC)` (sin prefijo `I`) |
| `@Component class FooAdapter implements IFooPort` | `class FooRepository(FooGateway)` — sufijo descriptivo: `Repository` / `Client` / `Service` / `Encoder` |
| `@RestController` + `@RequestMapping` | `APIRouter()` + `@router.post(...)` |
| `@Service` + `@Autowired` | Inyección manual por constructor; `Depends(...)` solo en `entry_points` |
| Lombok `@Data @Builder` | `@dataclass` (mutable) / `@dataclass(frozen=True)` (value object) |
| Bean Validation (`@Valid`) | Pydantic v2 (`BaseModel`, `Field`, validators) |
| `Optional<T>` | `T \| None` |
| `List<T>` / `Map<K, V>` | `list[T]` / `dict[K, V]` (built-ins, no `typing.List`) |
| JPA / Hibernate | SQLAlchemy 2.x async |
| Liquibase | Alembic |
| OpenFeign declarativo | httpx async — cliente concreto, no declarativo |
| `@Value("${...}")` | `pydantic-settings` (un solo `Settings`) |
| `try-with-resources` | `async with` / `with` |
| MapStruct | mapping manual `to_domain()` / `from_domain()` en el adapter |
| `application/` separada | todo bajo `infrastructure/entry_points/` |
| `RuntimeException` chain | `raise XError(...) from e` |

---

## Agregar un nuevo caso de uso (checklist)

1. Si hay nueva entidad o regla: agregar en `domain/model/`
2. Si el caso de uso necesita acceso a datos nuevo: agregar método en el gateway (`domain/model/gateways/`)
3. Crear el caso de uso en `domain/usecase/` con su `Command` o `Query`
4. Implementar el método nuevo en `infrastructure/driven_adapters/product_repository.py`
5. Agregar endpoint en `infrastructure/entry_points/api_rest/routers/`
6. Agregar dependency function en `dependencies.py`
7. Agregar test unitario en `tests/unit/domain/usecase/`
