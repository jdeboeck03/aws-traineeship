# AWS Traineeship 2026

Documentation site built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/).

## Local development

Requires Python 3.10+.

```bash
pip install -r requirements.txt
mkdocs serve
```

The site is available at <http://localhost:8000> with live reload on file changes.

## Publishing

The site is automatically published to GitHub Pages on every push to `main` via `.github/workflows/pages.yaml`.

To enable GitHub Pages on a new repository: go to **Settings → Pages** and set the source to **GitHub Actions**.
