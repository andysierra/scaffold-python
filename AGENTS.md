# AGENTS.md — Orquestador de Agentes y Specs

## Rol de este archivo

Este documento es el **punto de entrada del desarrollo guiado por specs (spec-driven development)**. Antes de implementar cualquier funcionalidad, el agente debe leer el spec correspondiente en [`/specs`](./specs/). Cada decisión de arquitectura, contrato de servicio, o estándar de implementación tiene su propio spec en esa carpeta. Este archivo no duplica ese contenido — lo referencia y da contexto de por qué existe.

---

## Declaración de intenciones

Construir un **microservicio de grado producción** en Python. No un ejercicio, no un dummy, no un proof of concept desechable.

El objetivo es aprender haciendo lo real: las mismas decisiones, los mismos trade-offs, y los mismos estándares que se aplican en sistemas que sirven tráfico real. Eso significa no escatimar en tecnologías, prácticas, diseño ni arquitectura — aunque añadan complejidad inicial.

---

## Stack y tecnologías

No se elige el stack mínimo viable para aprender; se elige el stack correcto para producción:

| Capa | Tecnología |
|---|---|
| Lenguaje | Python 3.12+ con tipado estricto |
| Framework | FastAPI (async-first) |
| Validación | Pydantic v2 |
| Base de datos | PostgreSQL + SQLAlchemy (async) + Alembic |
| Caché | Redis |
| Mensajería | (a definir en spec) |
| Contenerización | Docker single-stage con buenas prácticas |
| Orquestación local | Docker Compose (solo para dev) |
| Observabilidad | Structured logging + OpenTelemetry |
| Testing | pytest |
| Gestión de secretos | Variables de entorno + `.env` no commiteado |

---

## Arquitectura hexagonal y estructura de carpetas

Basada en el scaffold de Bancolombia (Java/Spring), adaptada a Python/FastAPI. Ver spec completo y equivalencias técnicas en [`specs/architecture.md`](./specs/architecture.md).

```
src/
  domain/
    models/              # Entidades y value objects de negocio
    gateways/            # Interfaces abstractas — puertos de salida
    services/            # Use cases concretos (orquestan models + gateways)
    exceptions.py        # DomainError + subclases tipadas
    messages.py          # ResponseCode + Messages enums
  infrastructure/
    driven_adapters/     # Adaptadores de SALIDA (implementan gateways)
      persistence/       # SQLAlchemy: base, session, ORM models, repositorios
      clients/           # Clientes HTTP externos (httpx)
      config/            # Wiring técnico (engine SQLAlchemy, Redis client)
    entry_points/        # Adaptadores de ENTRADA
      api_rest/
        routers/         # APIRouter por feature
        schemas/         # Pydantic Request/Response por feature
        security/        # Validación JWT, Principal, scopes
        dependencies.py  # FastAPI Depends — wiring de DI manual
        error_handlers.py # DomainError → respuesta JSON estructurada
        middleware.py    # X-Request-ID, logging del ciclo HTTP
  config.py
  main.py
tests/
  unit/                  # Espeja la estructura de src/domain/
specs/
Dockerfile
docker-compose.yml       # Solo para dev local; prod se provisiona vía IaC
pyproject.toml           # Deps + ruff + mypy + pytest config
sonar-project.properties # Config del análisis SonarQube
```

Regla fundamental: las dependencias solo apuntan hacia adentro — `infrastructure` → `domain`, nunca al revés.

---

## Estándares no negociables

- **Sin hardcoding**: toda configuración viene del entorno
- **Sin `latest`**: todas las imágenes y dependencias con versión pinneada
- **Sin secretos en código ni en git**
- **Tipado completo**: type hints en toda función pública, mypy en CI
- **Tests primero en lógica de negocio**: no se mergea código de dominio sin test
- **Errores explícitos**: HTTP errors con body estructurado, logs con contexto
- **Migraciones versionadas**: Alembic, nunca DDL manual en producción
- **Imagen non-root**: el proceso dentro del contenedor no corre como root
- **Contratos documentados**: OpenAPI generado automáticamente, siempre actualizado

---

## Buenas prácticas de microservicios

- **Un proceso, una responsabilidad**: si el servicio crece hacia dos dominios distintos, separar en servicios
- **Health checks**: `GET /health` (liveness) y `GET /ready` (readiness con verificación de DB/Redis)
- **Idempotencia**: los endpoints que mutan estado deben ser idempotentes donde sea posible
- **Graceful shutdown**: manejar `SIGTERM` para drenar conexiones antes de terminar
- **Correlation ID**: propagar `X-Request-ID` en todos los logs y respuestas para trazabilidad end-to-end
- **Sin lógica en `main.py`**: solo configuración del app, registro de routers y lifecycle hooks

---

## Buenas prácticas SonarQube

- **Cobertura mínima**: ≥ 90% en líneas; umbral configurado en el Quality Gate del servidor SonarQube
- **Cognitive complexity**: ≤ 15 por función; funciones largas se extraen
- **Sin duplicación**: bloques duplicados > 10 líneas se extraen a utilidades compartidas
- **Seguridad**: sin secretos hardcodeados, sin SQL construido con concatenación de strings, sin `eval()`
- **Bugs críticos en cero**: el Quality Gate falla si hay issues de severidad `BLOCKER` o `CRITICAL`
- La configuración del proyecto vive en `sonar-project.properties` en la raíz del repo (sources, tests, `host.url`, exclusiones, Quality Gate wait)
- El servidor SonarQube corre en Docker local (`http://localhost:9000` por defecto); el análisis se dispara con `sonar-scanner` desde el repo
- El token de autenticación se pasa por env var `SONAR_TOKEN` — **nunca** se commitea en el archivo
- `pytest` debe generar `coverage.xml` (`--cov-report=xml`) **antes** de correr `sonar-scanner` para que Sonar reciba la cobertura

---

## Specs en `/specs`

Cada área del sistema tiene su propio documento. Los agentes deben leer el spec relevante antes de implementar.

| Spec | Descripción |
|---|---|
| [`specs/business.md`](./specs/business.md) | Dominio de negocio del proyecto: glosario, entidades, lifecycle, use cases, reglas e invariantes — se llena por proyecto |
| [`specs/architecture.md`](./specs/architecture.md) | Arquitectura hexagonal: capas, gateways, reglas de importación, wiring de DI y checklist |
| [`specs/backend-standards.md`](./specs/backend-standards.md) | Estándares de código backend: tipado, estructura, convenciones, logging, containerización |
| [`specs/security.md`](./specs/security.md) | Autenticación JWT (validación), autorización por scopes, errores, CORS, configuración |
| [`specs/testing.md`](./specs/testing.md) | Estrategia de testing: scope unit-only, naming, qué se testea / qué no, cobertura, ejecución vía compose |
| *(por crear)* | Contratos de API y convenciones REST |
| *(por crear)* | Modelo de datos y estrategia de migraciones |

---

## Economía de tokens y disciplina de specs

Estos specs viajan al contexto del agente cada vez que se implementa una feature — un spec con grasa se paga en tokens en cada iteración. Reglas para mantenerlos magros:

- **Un tema por spec, sin solapes**: si dos specs hablan del mismo concepto, uno cross-referencia al otro (`[backend-standards.md](...)`), nunca copy-paste
- **Listas y tablas** antes que prosa narrativa — un agente parsea más rápido una tabla de 5 filas que un párrafo equivalente
- **Sin texto motivacional ni introducciones decorativas** — el primer párrafo ya dice qué regula la spec; nada de "este es un documento crucial que…"
- **Code snippets solo cuando muestran un patrón no obvio** — no para ilustrar lo evidente; si el código habla solo, va al repo, no al spec
- **Sin ejemplos largos** cuando una tabla de equivalencias basta (ver tabla Java↔Python en `architecture.md` como referencia)
- Cuando un spec supera ~300 líneas, **partirlo** en specs más pequeños y enfocados
- Reglas específicas a una feature concreta van en **código** (docstring, comentario justificado), no en spec — el spec es lo que aplica a todo el servicio
- En la implementación, el agente carga **solo el spec relevante a la tarea** — no todos los specs cada vez. `business.md` + el spec del área que se toca suele ser suficiente

---

## Lo que NO se versiona

- La carpeta `.claude/` nunca se commitea — contiene memoria y configuración local del agente, no es parte del proyecto

---

## Lo que deliberadamente se evita

- Atajos que funcionen "por ahora" pero no escalen
- Abstracciones prematuras sin necesidad real
- Código sin tipos ni validación
- Tests que mockean todo y no prueban nada real
- Documentación separada del código que inevitablemente se desactualiza
- Multi-stage Dockerfiles cuando una sola etapa cumple — la complejidad solo se justifica si reduce peso/superficie real
- Versionar la orquestación de **producción** en este repo — la infra de prod se provisiona vía IaC fuera del repo (`docker-compose.yml` es solo para dev local)
- Logs manuales de inicio/fin de request en routers o services — ese ciclo es trabajo del middleware, no del flujo de negocio
