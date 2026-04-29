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
| Contenerización | Docker con multi-stage builds |
| Orquestación local | Docker Compose |
| Observabilidad | Structured logging + OpenTelemetry |
| Testing | pytest |
| Gestión de secretos | Variables de entorno + `.env` no commiteado |

---

## Arquitectura hexagonal y estructura de carpetas

Basada en el scaffold de Bancolombia (Java/Spring), adaptada a Python/FastAPI. Ver spec completo y equivalencias técnicas en [`specs/architecture.md`](./specs/architecture.md).

```
src/
  domain/
    model/
      gateways/          # Interfaces abstractas (gateways/puertos de salida)
                         # Entidades, value objects y excepciones de dominio
    usecase/             # Casos de uso — orquestan modelo + gateways
  infrastructure/
    driven_adapters/     # Implementaciones de los gateways (DB, Redis, HTTP externo)
      db/                # Base SQLAlchemy, session, modelos ORM
    entry_points/        # Adaptadores de entrada
      api_rest/          # Routers FastAPI, dependencies, error handlers
  config.py
  main.py
tests/
  unit/                  # Espeja la estructura de src/domain/
specs/
Dockerfile
docker-compose.yml
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
- El análisis se ejecuta automáticamente al subir código al servidor SonarQube (Docker) — no se corre localmente

---

## Estrategia de testing

Solo tests unitarios con `pytest` y `pytest-mock`.

- Prueban lógica de dominio pura — los puertos se mockean, sin I/O real
- Priorizar cobertura de reglas de dominio, invariantes y flujos críticos antes que escenarios triviales o de infraestructura
- Nombrado: `test_dado<Contexto>_cuando<Accion>_entonces<ResultadoEsperado>`

---

## Specs en `/specs`

Cada área del sistema tiene su propio documento. Los agentes deben leer el spec relevante antes de implementar.

| Spec | Descripción |
|---|---|
| [`specs/architecture.md`](./specs/architecture.md) | Arquitectura hexagonal: capas, gateways, reglas de importación y checklist |
| *(por crear)* | Contratos de API y convenciones REST |
| *(por crear)* | Modelo de datos y estrategia de migraciones |
| *(por crear)* | Estrategia de testing |
| *(por crear)* | Seguridad y autenticación |
| [`specs/backend-standards.md`](./specs/backend-standards.md) | Estándares de código backend: tipado, estructura, convenciones y calidad |

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
