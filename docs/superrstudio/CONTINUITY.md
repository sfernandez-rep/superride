Quiero añadir las siguientes instrucciones a la sesión actual de desarrollo de **SuperRStudio**.

IMPORTANTE: Estas instrucciones son complementarias al MASTER DEVELOPMENT PROMPT original. No lo sustituyen, no modifican el alcance general del proyecto y no deben provocar que reinicies ninguna tarea ya realizada.

Continuá desde el estado actual del repositorio, respetando todas las decisiones de arquitectura, compatibilidad, funcionalidades y objetivos establecidos previamente.

## 1. CONTINUIDAD Y AUTONOMÍA

Quiero que trabajes de forma autónoma, avanzando por hitos verificables.

No te detengas solamente por completar la documentación, configurar dependencias o finalizar un módulo.

Una vez completado y probado un hito, continuá con el siguiente establecido en ROADMAP.md, siempre que el entorno y los recursos disponibles lo permitan.

Mantené el objetivo original de transformar RStudio en SuperRStudio, conservando las funcionalidades originales e incorporando:

- Interfaz gráfica moderna y personalizable.
- Modo visual y modo avanzado.
- Edición de datasets mediante tablas y selección de columnas.
- Gráficas ggplot2 editables visualmente.
- Menús contextuales, incluidos clic derecho y doble clic sobre elementos.
- Generación reproducible de código R.
- Análisis estadísticos visuales.
- Herramientas especializadas en biología, ecología y pesquería.
- Compatibilidad con paquetes de R y proyectos existentes.
- Windows 11, Windows 10 cuando resulte técnicamente viable y Ubuntu posteriormente.

No implementes todo simultáneamente. Priorizá estabilidad, compatibilidad y código mantenible.

## 2. PRIORIDAD INMEDIATA

Continuá primero con la preparación del entorno y la compilación de la versión original de RStudio 2026.10.0.

Ya realizaste avances importantes instalando Visual Studio 2026, herramientas C++, SDK, CMake y otras dependencias.

No repitas instalaciones correctamente verificadas.

Tu prioridad es:

1. Completar la verificación de dependencias.
2. Configurar correctamente la compilación.
3. Compilar la aplicación original.
4. Ejecutar pruebas básicas de funcionamiento.
5. Registrar errores y soluciones.
6. Establecer una base reproducible.

Si la compilación completa queda bloqueada, documentá exactamente el problema, el comando utilizado y la evidencia. No declares el build exitoso sin comprobarlo.

Después avanzá con la arquitectura modular de SuperRStudio y el primer módulo visual real.

## 3. GRAPHIFY COMO HERRAMIENTA PRIORITARIA

Quiero priorizar Graphify frente a Ponytail para comprender la estructura y las dependencias del código de RStudio.

Investigá qué herramienta Graphify corresponde realmente a análisis de repositorios y grafos de dependencias de código.

No confundas productos con nombres similares.

Verificá:

- Repositorio y documentación oficial.
- Compatibilidad con Codex y Claude Code.
- Compatibilidad con Windows.
- Soporte para C++, Java/GWT, TypeScript y JavaScript.
- Capacidades de análisis de dependencias y símbolos.
- Requisitos, costos, licencias y permisos.
- Si funciona localmente o necesita enviar código a un servicio externo.
- Mantenimiento y seguridad.

Si existe una integración apropiada, confiable y compatible, instalala y configurala cuando sea seguro.

Si requiere credenciales, suscripciones, permisos adicionales o transmisión de código a un servicio externo, documentalo y solicitá autorización antes de habilitarlo.

Si Graphify no resulta adecuado, investigá alternativas confiables para análisis de dependencias y estructura de grandes repositorios, sin bloquear el proyecto.

No instales Ponytail por ahora. Solo consideralo posteriormente si existe una necesidad concreta.

## 4. CONTINUIDAD ENTRE CODEX Y CLAUDE CODE

Quiero que este proyecto pueda desarrollarse con ambos agentes, aprovechando sus respectivas cuotas de uso.

Creá y mantené actualizado un archivo HANDOFF.md en la raíz del repositorio.

Este archivo debe incluir:

- Objetivo general de SuperRStudio.
- Estado actual del desarrollo.
- Rama activa y último commit.
- Versión exacta de RStudio utilizada como upstream.
- Arquitectura identificada.
- Dependencias instaladas.
- Herramientas y versiones utilizadas.
- Comandos de compilación.
- Resultado de las últimas pruebas.
- Errores conocidos.
- Cambios sin finalizar.
- Funcionalidades implementadas y verificadas.
- Siguiente tarea exacta.
- Instrucciones para que otro agente continúe sin repetir trabajo.

Actualizá HANDOFF.md al completar cada hito importante y antes de terminar la sesión.

Mantené coherentes AGENTS.md y CLAUDE.md para que ambos agentes sigan los mismos principios técnicos.

Prepará instrucciones de continuación para Claude Code cuando sea necesario.

No afirmes que realizaste una transferencia automática entre agentes a menos que realmente exista una integración funcional y verificada.

## 5. USO EFICIENTE DEL CONTEXTO Y LAS CUOTAS

Estoy utilizando Codex con una ventana de uso limitada de cinco horas.

Quiero aprovechar esa cuota para producir avances reales.

Por lo tanto:

- Priorizá tareas de ingeniería sobre explicaciones extensas.
- Evitá análisis repetitivos sin nueva evidencia.
- Reutilizá los resultados de investigaciones anteriores.
- No reinstales dependencias ya verificadas.
- No rehagas documentación innecesariamente.
- Realizá commits frecuentes y coherentes.
- Mantené un estado del proyecto recuperable.
- Utilizá compactación de contexto si el entorno lo admite.
- No supongas que podés conocer con precisión la cuota restante si la extensión no proporciona esa información.
- No inicies automáticamente otro agente mediante comandos no verificados.

Si detectás que la sesión está próxima a finalizar o el entorno informa un límite, priorizá guardar cambios, ejecutar las pruebas posibles, actualizar HANDOFF.md y dejar instrucciones concretas para continuar.

Si no podés detectar el límite, mantené el estado recuperable durante todo el desarrollo.

No esperes a los últimos momentos para documentar lo realizado.

## 6. GIT Y GITHUB

El repositorio oficial del proyecto es:

https://github.com/sfernandez-rep/superride

(Renombrado desde `superrstudio` el 2026-10-29 por decisión del propietario; la
URL anterior redirige. El producto público se llama SuperR.)

Trabajá sobre el fork existente.

No vuelvas a crear el repositorio.

Conservá la relación con upstream.

Realizá commits pequeños, con mensajes descriptivos.

Subí los avances verificados al repositorio cuando sea apropiado y seguro.

Nunca uses force push ni sobrescribas cambios ajenos.

No incluyas instaladores temporales, archivos grandes de compilación, secretos, credenciales ni datasets privados.

No modifiques otras carpetas o proyectos que no correspondan a SuperRStudio.

## 7. COMPILACIÓN Y DESARROLLO MULTIPLATAFORMA

Windows 11 x64 es el sistema principal de desarrollo.

Windows 10 x64 debe mantenerse como objetivo experimental mientras se investiga su compatibilidad.

Ubuntu 24.04 LTS x64 es el siguiente sistema objetivo.

Evitá introducir dependencias innecesariamente exclusivas de Windows.

Conservá la infraestructura multiplataforma original de RStudio siempre que sea posible.

## 8. SIGUIENTE FUNCIONALIDAD DESPUÉS DE COMPILAR

Cuando la versión original compile y se ejecute correctamente, comenzá a implementar una primera funcionalidad real de SuperRStudio:

Un flujo de trabajo que permita seleccionar columnas de un dataset desde una interfaz visual y generar una gráfica mediante ggplot2 sin escribir manualmente R.

La funcionalidad debe reutilizar la sesión R existente.

El código generado debe ser reproducible.

Primero construí una implementación mínima completamente funcional.

Después incorporá propiedades visuales y edición interactiva.

No sustituyas funcionalidad real por una maqueta.

## 9. SEGURIDAD Y CALIDAD

Mantené las obligaciones de la licencia AGPLv3 y de terceros.

No desactives protecciones de Windows, antivirus, controles UAC o mecanismos de seguridad para evitar bloqueos.

No ejecutes scripts desconocidos de terceros sin inspeccionarlos.

No realices cambios destructivos.

No modifiques configuraciones globales innecesariamente.

No declares completadas funcionalidades que no hayan sido implementadas y verificadas.

## 10. INSTRUCCIÓN FINAL

Continuá la ejecución actual desde donde estás.

No reinicies el proyecto.

No vuelvas a clonar RStudio.

No abandones el plan maestro original.

Tu objetivo inmediato es obtener la compilación original funcional y, a partir de ella, avanzar progresivamente en SuperRStudio.

Trabajá hasta completar un hito o encontrar un bloqueo real, dejando siempre el repositorio y HANDOFF.md en un estado recuperable para Codex o Claude Code.