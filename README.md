# Backup local de workflows n8n

Este proyecto descarga tus workflows de n8n Cloud a archivos JSON locales.

## Requisitos

- Tener una API key activa en n8n Cloud
- Tener `curl` y `python3` instalados

## Instalar dependencias

En macOS normalmente ya vienen instalados, pero puedes verificarlo con:

```bash
curl --version
python3 --version
```

Si alguno no existe y usas Homebrew:

```bash
brew install curl python
```

Si no tienes Homebrew, puedes instalarlo con:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## Variables de entorno

1. Crea tu archivo local a partir del ejemplo:

```bash
cp .env.example .env.local
```

2. Edita `.env.local` y completa al menos estas variables:

```env
N8N_BASE_URL="https://TU_SUBDOMINIO.n8n.cloud"
N8N_API_KEY="TU_API_KEY"
```

3. Si luego quieres reutilizar este proyecto para otros scripts, tambien puedes guardar una de estas llaves en `.env.local`:

```env
OPENAI_API_KEY=""
GEMINI_API_KEY=""
```

`backup-n8n.sh` carga `.env.local` automaticamente al ejecutarse.

Nunca subas `.env.local` a git. Ese archivo es solo local y ya esta incluido en `.gitignore`.

## Ejecutar backup

Desde esta carpeta:

```bash
chmod +x backup-n8n.sh
./backup-n8n.sh
```

Ese comando descarga todos los workflows accesibles por tu API key.

Si ejecutas el script sin configurar las variables, te pedira crear `.env.local` a partir de `.env.example`, completar `N8N_API_KEY` y `N8N_BASE_URL`, y mantener ese archivo fuera de git.

## Respaldar un unico workflow

Tambien puedes respaldar un solo flujo pasando el ID como argumento:

```bash
./backup-n8n.sh rgdmh6DBYQK23Djf
```

Eso crea este archivo:

```bash
workflows/rgdmh6DBYQK23Djf.json
```

Tambien actualiza `workflows/manifest.json` con la metadata del backup actual. Si el manifest ya existe, el workflow se agrega o actualiza sin borrar los demas.

## Como obtener el ID de un workflow

Toma el ID directamente desde la URL del workflow abierto en n8n Cloud.

Ejemplo:

```text
https://simianlab.app.n8n.cloud/workflow/rgdmh6dbyqk23djf
```

En ese caso, el ID es:

```text
rgdmh6dbyqk23djf
```

## Archivos generados

Se guardan dentro de `workflows/`:

- `workflows/manifest.json`: resumen del backup actual, fecha en zona `America/Bogota`, cantidad y lista de workflows
- `workflows/_workflows_index.json`: lista completa de workflows
- `workflows/_workflow_ids.txt`: IDs encontrados
- `workflows/<id>.json`: backup individual por workflow

Dentro de `manifest.json`, cada workflow incluye dos fechas distintas:

- `n8nUpdatedAt`: ultima fecha de actualizacion del workflow en n8n
- `backedUpAt`: fecha y hora en que ese workflow fue respaldado localmente

## Solucion de problemas

- Si ves `unauthorized`, revisa `N8N_API_KEY` en `.env.local`
- Si no se generan archivos, revisa `N8N_BASE_URL` y que la API key pertenezca al workspace correcto
- Si cambias la API key, solo actualiza `.env.local` y vuelve a correr el script
- Si quieres probar primero, usa `./backup-n8n.sh <workflow_id>` con un solo flujo
