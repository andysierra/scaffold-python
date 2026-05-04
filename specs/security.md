# Spec: Seguridad

Estándares de autenticación y autorización para microservicios construidos con este scaffold. Todo endpoint que mute estado o exponga datos sensibles debe pasar por estos controles.

---

## Posición del servicio

Este scaffold **valida** JWTs — no los emite. La emisión (login, refresh) es responsabilidad de un IdP central o de un servicio de auth dedicado. El servicio recibe el token en `Authorization: Bearer <token>`, lo valida, y deriva el `Principal` desde sus claims.

Si en algún proyecto el servicio también necesita **emitir** tokens, eso requiere una sección adicional (firma, rotación de claves, almacenamiento de refresh tokens, rate limiting de login) — fuera del scope por defecto de este spec.

---

## Autenticación (JWT)

### Algoritmo

Dos modos soportados:

- **RS256** (recomendado): firma asimétrica. El servicio guarda solo la clave **pública** del IdP (`JWT_PUBLIC_KEY`). Si el IdP rota claves, se obtiene de un endpoint JWKS — eso requiere un cliente HTTP en `infrastructure/driven_adapters/clients/` y queda fuera del scope mínimo.
- **HS256**: secreto compartido (`JWT_SECRET`). Solo válido para entornos donde el IdP y el servicio son operados por el mismo equipo; nunca compartir el secreto entre dominios de confianza distintos.

### Validaciones obligatorias en cada token

1. Firma criptográfica
2. Expiración (`exp`) — token no expirado, con `leeway` configurable para skew de reloj
3. Issuer (`iss`) — debe matchear `JWT_ISSUER`
4. Audience (`aud`) — debe contener `JWT_AUDIENCE`
5. `nbf` (not before) si está presente
6. Claims requeridos: `sub`, `exp` (mínimo)

Cualquier validación que falle → `InvalidTokenError` o `ExpiredTokenError`. Nunca devolver detalles internos del fallo en el body de la respuesta — solo loguearlos (a `WARNING`) con `request_id` para correlación.

### Librería

`pyjwt`. Prohibido `python-jose` (abandonware con CVEs históricas).

---

## Autorización

Por **scopes** transportados en el JWT como claim. La autorización se aplica a nivel de **endpoint**, no de service.

Recomendación: scopes con formato `<recurso>:<acción>` — ej.: `subscriptions:read`, `subscriptions:write`, `users:admin`. Más fino que roles y compatible con OAuth2.

```python
@router.post(
    "/subscriptions",
    dependencies=[Depends(require_scopes("subscriptions:write"))],
)
async def create_subscription(
    body: CreateSubscriptionRequest,
    principal: Annotated[Principal, Depends(get_current_user)],
    service: Annotated[CreateSubscriptionService, Depends(get_create_subscription_service)],
) -> ApiResponse[SubscriptionResponse]:
    ...
```

### Reglas

- Los **services del dominio nunca verifican autorización** — eso es responsabilidad del entry point. El service recibe ya autenticado y autorizado, y se enfoca en lógica de negocio.
- Si el service necesita el `user_id`, el router lo pasa explícito como parte del `Command` — el dominio no conoce el tipo `Principal`.
- `require_scopes(*scopes: str)` exige **todos** los scopes listados (AND); si querés OR, usá `require_any_scope(*scopes: str)`.
- Los endpoints **públicos** (health, docs, login si existiera) son la excepción y deben estar listados explícitamente en el código — por defecto todo requiere auth.

---

## Estructura

Toda la seguridad vive en `infrastructure/entry_points/api_rest/security/`:

```
security/
  jwt_validator.py    # JwtValidator: parsea + valida firma/exp/iss/aud → Principal
  principal.py        # Principal (dataclass frozen): user_id, scopes, claims
  dependencies.py     # get_current_user, require_scopes, require_any_scope
  exceptions.py       # InvalidTokenError, ExpiredTokenError, InsufficientScopeError
```

`Principal` es un value object inmutable:

```python
@dataclass(frozen=True, slots=True)
class Principal:
    user_id: UUID
    scopes: frozenset[str]
    claims: Mapping[str, Any]   # claims crudos por si el endpoint necesita más

    def has_scope(self, scope: str) -> bool:
        return scope in self.scopes
```

`JwtValidator` recibe la configuración (`Settings`) por constructor y se expone como singleton vía `app.state` (igual que el engine de DB).

---

## Errores

Se agregan a `domain/exceptions.py` (heredan de `DomainError`). Códigos correspondientes en `ResponseCode`, mensajes en `Messages`.

| Excepción | `code` | `message` (Spanish) | HTTP |
|---|---|---|---|
| `UnauthorizedError` | `1401` | "No autenticado" | 401 |
| `InvalidTokenError` | `1401` | "Token inválido" | 401 |
| `ExpiredTokenError` | `1401` | "Token expirado" | 401 |
| `ForbiddenError` | `1403` | "Permiso insuficiente" | 403 |
| `InsufficientScopeError` | `1403` | "Scope requerido no presente" | 403 |

`UnauthorizedError` y derivadas (`InvalidTokenError`, `ExpiredTokenError`) deben incluir el header `WWW-Authenticate: Bearer` en la respuesta — el `error_handler` global lo agrega cuando el `code` empieza con `14`.

El body sigue el envelope estándar `{code, message, detail}`. **Nunca** incluir el token, la signature, ni la razón técnica del fallo en `detail` — solo identificadores correlacionables (`request_id`).

---

## Configuración

En `Settings` (Pydantic):

```python
jwt_algorithm: Literal["RS256", "HS256"] = "RS256"
jwt_public_key: str | None = None      # requerido si RS256
jwt_secret: str | None = None          # requerido si HS256
jwt_issuer: str
jwt_audience: str
jwt_leeway_seconds: Annotated[int, Field(ge=0, le=300)] = 0
```

Validación cruzada con `model_validator(mode="after")`:
- Si `jwt_algorithm == "RS256"` ⇒ `jwt_public_key` requerido
- Si `jwt_algorithm == "HS256"` ⇒ `jwt_secret` requerido
- `jwt_secret` y `jwt_public_key` **nunca** tienen default en código (falla rápido si faltan)

---

## Logging y trazabilidad

- Toda autenticación fallida se loguea a `WARNING` con: razón del fallo (categoría, no stack trace), `sub` si está disponible, `request_id`. **Nunca** el token ni la signature.
- `request_id` (del middleware) + `user_id` (del `Principal`) en contexto de log para todas las requests autenticadas — usar `structlog.contextvars.bind_contextvars` justo después de validar el token
- Toda autorización fallida (scope insuficiente) se loguea a `WARNING` con `user_id`, `required_scopes`, `granted_scopes`, `request_id`

---

## CORS

Política explícita por configuración. **Prohibido** `Access-Control-Allow-Origin: *` en `prod` y `staging`.

### Configuración (`Settings`)

```python
cors_allow_origins: list[str] = Field(default_factory=list)
cors_allow_methods: list[str] = Field(default_factory=lambda: ["GET", "POST", "PUT", "DELETE", "PATCH"])
cors_allow_headers: list[str] = Field(default_factory=lambda: ["Authorization", "Content-Type"])
cors_allow_credentials: bool = False
cors_max_age_seconds: Annotated[int, Field(ge=0, le=86400)] = 600
```

### Reglas

- `cors_allow_origins`: lista explícita de origins permitidos (URLs completas, ej.: `https://app.example.com`). **Nunca** `["*"]` en `prod`/`staging` — se valida con `model_validator` y se rechaza al arrancar.
- `cors_allow_credentials = True` requiere lista concreta de origins (la spec CORS prohíbe `*` con credentials). Activar **solo** si el servicio recibe cookies o Basic Auth — el JWT en `Authorization` header **no** lo requiere.
- `cors_allow_methods` y `cors_allow_headers`: enumerar solo lo que el servicio realmente usa. Sumar custom headers (`X-Idempotency-Key`, etc.) cuando se introduzcan.
- `cors_max_age_seconds`: cache del preflight `OPTIONS`. Default 600s (10 min). Subir cautelosamente — invalidar requiere esperar el TTL.

### Aplicación

`fastapi.middleware.cors.CORSMiddleware` registrado en `main.py` con los valores de `Settings`. **Va antes** del `RequestIdMiddleware` para que el preflight `OPTIONS` no entre al stack de logging del request.

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allow_origins,
    allow_methods=settings.cors_allow_methods,
    allow_headers=settings.cors_allow_headers,
    allow_credentials=settings.cors_allow_credentials,
    max_age=settings.cors_max_age_seconds,
)
app.add_middleware(RequestIdMiddleware)
```

---

## Lo que NO está en scope

- Refresh tokens
- Token revocation / blacklist
- mTLS entre servicios
- Rate limiting por usuario o IP
- API keys (alternativa a JWT)
- OAuth2 flows completos (authorization code, device, etc.)
- Multi-factor authentication
- Session management

Si un proyecto necesita alguno de estos, se agrega como sección a este spec o como spec separado — pero no se implementa "por si acaso".
