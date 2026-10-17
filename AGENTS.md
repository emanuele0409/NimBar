# Regole permanenti NimBar

- Sicurezza prima delle funzionalità; minimo privilegio.
- Nessuna telemetria o tracking. L'unica rete a runtime ammessa è il controllo in sola lettura delle GitHub Releases, manuale o secondo la preferenza esplicita dell'utente.
- Non usare API private senza approvazione esplicita dell'utente.
- Non aggiungere dipendenze inutili o helper persistenti.
- Non modificare impostazioni di sistema, Gatekeeper o SIP.
- Non disabilitare App Sandbox senza approvazione esplicita.
- Non dichiarare test, prestazioni o compatibilità senza verificarli.
- I test unitari non devono alterare la barra reale dell'utente.
- Non pubblicare automaticamente repository, codice o release.
- Mantenere il target macOS 27 fino a verifica di compatibilità più ampia.
- Documentare decisioni architetturali e rischi residui.
- Nessun comportamento automatico che nasconda o sposti icone senza consenso.

## Agent skills

### Issue tracker

Issues and specs live as Markdown files under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the five canonical labels configured for this repo. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
