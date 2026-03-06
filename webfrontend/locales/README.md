# Adding a new language

All UI strings are in the JSON files in this folder. The app **discovers** available locales from the `*.json` files here; no code change is needed to “register” a new language.

## 1. Add the locale file

Create a new file `{code}.json` in `webfrontend/locales/`, using the same structure as `en.json`.

- **Code**: Use a locale code such as `es` (Spanish), `de` (German), `fr` (French). For regional variants you can use e.g. `pt-BR`, `es-ES`.
- **Structure**: Copy `en.json` and translate all **values** (keep the **keys** unchanged).
- **Metadata**: Set `meta.lang` to the locale code and `meta.name` to the language name as shown in the dropdown (e.g. `"Español"`, `"Deutsch"`).

Sections in the JSON: `meta`, `common`, `home`, `result`, `about`, `footer`, `errors`.

After adding the file, the new language is **available** and will appear in the selector by default.

## 2. (Optional) Limit which locales an instance shows

To expose only a subset of the available locales in a given deployment (e.g. only English), set the **environment variable** `ENABLED_LOCALES` to a comma-separated list of codes:

```bash
docker run -e ENABLED_LOCALES=en testssl-portal
# or several:
docker run -e ENABLED_LOCALES=pt-PT,en testssl-portal
```

Only codes that have a corresponding `{code}.json` in this folder are accepted. If `ENABLED_LOCALES` is unset, all available locales are enabled.

## Summary

| Step | Action |
|------|--------|
| 1 | Add `webfrontend/locales/{code}.json` (copy from `en.json`, translate, set `meta.lang` and `meta.name`). |
| 2 | Optional: set `ENABLED_LOCALES` in the environment to restrict which locales this instance offers. |

No changes are needed in Python or templates; the dropdown uses the new file and displays `meta.name`.
