# Handoff: Ingress rewrite breaks frontend assets (white page)

**Date:** 2026-09-26 · **Source:** sdd-frontend (spec 003-shortener-form) · **Severity:** high — site is broken in dev

## Symptom

https://demo.vijote.dev renders an unstyled white page; the shortening form does not work. Browser console shows the JS module was refused because it was served as `text/html`.

## Evidence

- Live HTML is a 003 build referencing `/assets/index-DaMkeDWv.js` and `/assets/index-Dk8xwhMS.css`.
- Requests for those exact paths return `200` with `Content-Type: text/html` (body = `index.html`).
- The deployed image is self-consistent: built locally from the same commit and inspected — both asset files exist in `/usr/share/nginx/html/assets/`. The files exist in the pod but are never served.
- Hard refresh does not fix it (not browser cache).

## Root cause

`terraform/environments/dev/manifests/app-frontend-ingress.yaml` sets these annotations at the **ingress level**:

```yaml
nginx.ingress.kubernetes.io/use-regex: "true"
nginx.ingress.kubernetes.io/rewrite-target: /$2
```

Ingress-nginx applies them to **every path in the ingress**, not just `/api`. The frontend rule is `path: /` (Prefix) with no capture groups, so `$2` is empty and **every non-`/api` request — including `/assets/*` — is rewritten to `/`** before proxying to the frontend nginx. The SPA fallback (`try_files … /index.html`) then returns `index.html` as `text/html`.

The comment in the manifest ("frontend / rule unaffected") is incorrect. Timeline: `012-5` introduced the annotations but its apply was rejected (K8s 1.28 strict decoding); `012-6` (Sep 23) fixed placement and **activated** the rewrite on all paths.

## Proposed fix (one line)

Make the frontend path capture the rest of the URL so the rewrite becomes an identity:

```yaml
- path: /(.*)            # was: / (Prefix)
  pathType: ImplementationSpecific
  backend:
    service:
      name: app-frontend
      port:
        number: 80
```

- `/assets/index.js` → `$2 = assets/index.js` → rewritten to itself → file served.
- `/` → `$2 = ""` → `/` → app shell.
- `/api(/|$)(.*)` rule unchanged.

Alternative: split into two Ingresses (one with the `/api` regex+rewrite, one for `/` without annotations). The single-ingress capture fix is smaller.

## Verification after apply

```sh
curl -sI https://demo.vijote.dev/assets/index-DaMkeDWv.js | grep -i content-type   # expect application/javascript
curl -sI https://demo.vijote.dev/assets/index-Dk8xwhMS.css | grep -i content-type  # expect text/css
curl -s  https://demo.vijote.dev/api/health 2>/dev/null                            # backend still reachable
```

Then hard-refresh the page: Tailwind styles applied, form shortens a URL end-to-end.
