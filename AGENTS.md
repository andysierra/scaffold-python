# AGENTS.md — Orquestador de Agentes y Specs

## Rol de este archivo

Este documento es el **punto de entrada y volante de orquestación** del proyecto. Dirige a los agentes hacia los specs específicos que viven en [`/specs`](./specs/). Cada decisión de arquitectura, contrato de servicio, o estándar de implementación tiene su propio spec en esa carpeta. Este archivo no duplica ese contenido — lo referencia y da contexto de por qué existe.

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
| Testing | pytest + testcontainers |
| CI | (a definir en spec) |
| Gestión de secretos | Variables de entorno + `.env` no commiteado |

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

## Specs en `/specs`

Cada área del sistema tiene su propio documento. Los agentes deben leer el spec relevante antes de implementar.

| Spec | Descripción |
|---|---|
| *(por crear)* | Arquitectura general y estructura de carpetas |
| *(por crear)* | Contratos de API y convenciones REST |
| *(por crear)* | Modelo de datos y estrategia de migraciones |
| *(por crear)* | Estrategia de testing |
| *(por crear)* | Observabilidad: logging, métricas y trazas |
| *(por crear)* | Pipeline CI/CD |
| *(por crear)* | Seguridad y autenticación |

---

## Lo que deliberadamente se evita

- Atajos que funcionen "por ahora" pero no escalen
- Abstracciones prematuras sin necesidad real
- Código sin tipos ni validación
- Tests que mockean todo y no prueban nada real
- Documentación separada del código que inevitablemente se desactualiza
