"""Renders the chart index page from a Helm index.yaml (as JSON on stdin).

Usage: yq -o=json index.yaml | python3 render_index.py <template> > index.html
"""
import json
import sys
from html import escape

REPO = "https://github.com/tinycloud-labs/helm"


def render_chart(name, versions):
    versions = sorted(versions, key=lambda v: v.get("created", ""), reverse=True)
    latest = versions[0]
    version = latest["version"]
    description = latest.get("description") or ""

    title = f'<a class="name" href="{REPO}/tree/main/charts/{escape(name)}">{escape(name)}</a>'
    release = f'{REPO}/releases/tag/{escape(name)}-{escape(version)}'
    html = [
        '  <div class="chart">',
        '    <div class="head">',
        f'      {title}',
        f'      <a class="version" href="{release}">{escape(version)}</a>',
        '    </div>',
        f'    <p>{escape(description)}</p>',
        f'    <pre><code>helm install {escape(name)} tinycloud-labs/{escape(name)} --version {escape(version)}</code></pre>',
    ]
    if len(versions) > 1:
        older = versions[1:]
        label = "older version" if len(older) == 1 else "older versions"
        listed = ", ".join(escape(v["version"]) for v in older)
        html.append(f'    <details><summary>{len(older)} {label}</summary>{listed}</details>')
    html.append('  </div>')
    return "\n".join(html)


def main():
    template_path = sys.argv[1]
    index = json.load(sys.stdin)
    charts = "\n".join(
        render_chart(name, versions)
        for name, versions in sorted(index.get("entries", {}).items())
    )
    generated = (index.get("generated") or "")[:10]
    with open(template_path) as f:
        page = f.read()
    sys.stdout.write(page.replace("{{CHARTS}}", charts).replace("{{GENERATED}}", escape(generated)))


if __name__ == "__main__":
    main()
