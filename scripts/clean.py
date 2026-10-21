#!/usr/bin/env python3
"""Normalise an n8n workflow for version control.

Reads workflow JSON (raw API export or MCP get_workflow_details payload) on stdin,
writes a cleaned, stably-formatted definition to stdout:
  - drops runtime/volatile fields (timestamps, version IDs, scopes, pinned data)
  - redacts hard-coded secrets by pattern, so they never reach git

Redacted values become REDACTED_* placeholders. The fix is to move the value into an
n8n credential; the placeholder is only there so the export is safe to commit.
"""
import json
import re
import sys

REDACTIONS = [
    # Authorization: Bearer <literal token> (expressions and existing placeholders are left alone)
    (re.compile(r'Bearer (?!REDACTED|YOUR_|\{\{|=)[A-Za-z0-9_\-.]{12,}'), 'Bearer REDACTED_TOKEN'),
    # Notion integration tokens
    (re.compile(r'\b(?:ntn|secret)_[A-Za-z0-9]{30,}'), 'REDACTED_NOTION_TOKEN'),
    # API keys passed as query-string parameters
    (re.compile(r'([?&](?:key|api_key|apikey|access_token|token)=)(?!REDACTED|\{\{|YOUR)[A-Za-z0-9_\-]{10,}', re.I),
     r'\1REDACTED_API_KEY'),
    # Common provider key formats
    (re.compile(r'\bsk-(?:ant-)?[A-Za-z0-9_\-]{20,}'), 'REDACTED_API_KEY'),
    (re.compile(r'\b\d{8,10}:AA[A-Za-z0-9_\-]{30,}'), 'REDACTED_TELEGRAM_BOT_TOKEN'),
    (re.compile(r'\bgh[pousr]_[A-Za-z0-9]{30,}'), 'REDACTED_GITHUB_TOKEN'),
    (re.compile(r'\bxox[abpr]-[A-Za-z0-9\-]{10,}'), 'REDACTED_SLACK_TOKEN'),
    (re.compile(r'\bAIza[0-9A-Za-z_\-]{35}'), 'REDACTED_GOOGLE_API_KEY'),
]


def redact(value):
    if isinstance(value, str):
        for pattern, repl in REDACTIONS:
            value = pattern.sub(repl, value)
        return value
    if isinstance(value, list):
        return [redact(v) for v in value]
    if isinstance(value, dict):
        return {k: redact(v) for k, v in value.items()}
    return value


def clean(wf):
    wf = wf.get('workflow', wf)
    settings = dict(wf.get('settings') or {})
    settings.pop('availableInMCP', None)
    meta = dict(wf.get('meta') or {})
    meta.pop('instanceId', None)
    return redact({
        'id': wf['id'],
        'name': wf['name'],
        'active': wf.get('active', False),
        'tags': sorted(t['name'] if isinstance(t, dict) else t for t in wf.get('tags') or []),
        'settings': settings,
        'nodes': wf['nodes'],
        'connections': wf['connections'],
        'meta': meta,
    })


if __name__ == '__main__':
    json.dump(clean(json.load(sys.stdin)), sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write('\n')
