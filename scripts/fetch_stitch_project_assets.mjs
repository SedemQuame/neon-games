#!/usr/bin/env node
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const projectId = '2763817086568591522';
const outputDir = path.resolve('stitch_exports/glory_grid_arcade_fintech');
const mcpUrl = 'https://stitch.googleapis.com/mcp';

const screens = [
  ['live-game', 'Live Game', 'e0bdff11c5fe4df988623bc1cb8016c3'],
  ['deposit', 'Deposit', 'ee49cb50ee5b47048ed85cbd9f595f8c'],
  ['lobby-dashboard', 'Lobby Dashboard', 'cae3d86750614dba8c343fffabb53112'],
  ['wallet', 'Wallet', '1ffd15a4ab584a778ba0ae03832b1455'],
  ['multiplayer-rooms', 'Multiplayer Rooms', '6a89a30ed05a475bbdec6e9c5ece4de5'],
  [
    'design-system',
    'Design System',
    'asset-stub-assets-becf2b4eedcd47319bb16eccc4c7b4e9-1777811414446',
  ],
];

function readJson(filePath) {
  return JSON.parse(readFileSync(filePath, 'utf8'));
}

function getQuotaProject() {
  if (process.env.STITCH_QUOTA_PROJECT) return process.env.STITCH_QUOTA_PROJECT;

  const adcPath = path.join(
    process.env.HOME,
    '.config/gcloud/application_default_credentials.json',
  );
  if (existsSync(adcPath)) {
    const adc = readJson(adcPath);
    if (adc.quota_project_id) return adc.quota_project_id;
  }

  const activeConfig = path.join(
    process.env.HOME,
    '.config/gcloud/configurations/config_default',
  );
  if (existsSync(activeConfig)) {
    const match = readFileSync(activeConfig, 'utf8').match(/^project\s*=\s*(.+)$/m);
    if (match) return match[1].trim();
  }

  return '';
}

async function getAccessToken() {
  if (process.env.STITCH_ACCESS_TOKEN) return process.env.STITCH_ACCESS_TOKEN;

  const adcPath = path.join(
    process.env.HOME,
    '.config/gcloud/application_default_credentials.json',
  );
  if (!existsSync(adcPath)) {
    throw new Error(
      'No Google Application Default Credentials found. Sign in with Google first, or set STITCH_ACCESS_TOKEN.',
    );
  }

  const adc = readJson(adcPath);
  const body = new URLSearchParams({
    client_id: adc.client_id,
    client_secret: adc.client_secret,
    refresh_token: adc.refresh_token,
    grant_type: 'refresh_token',
  });
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  const token = await response.json();
  if (!token.access_token) {
    throw new Error(`Could not refresh Google access token: ${JSON.stringify(token)}`);
  }
  return token.access_token;
}

function getApiKey() {
  if (process.env.STITCH_API_KEY) return process.env.STITCH_API_KEY;

  const mcpConfigPath = path.resolve('game_trader_app/mcp.json');
  if (existsSync(mcpConfigPath)) {
    const config = readJson(mcpConfigPath);
    return config.mcpServers?.stitch?.headers?.['X-Goog-Api-Key'] ?? '';
  }

  return '';
}

async function callMcpTool(accessToken, quotaProject, toolName, args) {
  const headers = {
    'Content-Type': 'application/json',
    Accept: 'application/json, text/event-stream',
  };
  if (accessToken.startsWith('api-key:')) {
    headers['X-Goog-Api-Key'] = accessToken.slice('api-key:'.length);
  } else {
    headers.Authorization = `Bearer ${accessToken}`;
    if (quotaProject) headers['x-goog-user-project'] = quotaProject;
  }

  const response = await fetch(mcpUrl, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: Date.now(),
      method: 'tools/call',
      params: { name: toolName, arguments: args },
    }),
  });

  const json = await response.json();
  if (json.error) {
    throw new Error(JSON.stringify(json.error));
  }
  if (json.result?.isError) {
    const message =
      json.result.content?.map((item) => item.text).filter(Boolean).join('\n') ||
      'Unknown Stitch MCP error';
    throw new Error(message);
  }
  return extractPayload(json.result);
}

function extractPayload(result) {
  if (result.structuredContent) return result.structuredContent;

  for (const item of result.content ?? []) {
    if (item.type !== 'text' || !item.text) continue;
    try {
      return JSON.parse(item.text);
    } catch {
      return item.text;
    }
  }

  return result;
}

function firstDownloadUrl(...files) {
  for (const file of files) {
    const url = file?.downloadUrl || file?.url || file?.uri;
    if (url) return url;
  }
  return '';
}

function fullResolutionImageUrl(url) {
  if (!url) return url;
  if (!url.includes('googleusercontent.com/')) return url;
  if (/=[A-Za-z0-9_-]+$/.test(url)) return url;
  return `${url}=s0`;
}

function download(url, outPath) {
  mkdirSync(path.dirname(outPath), { recursive: true });
  const result = spawnSync(
    'curl',
    ['-L', '-f', '-sS', '--compressed', url, '-o', outPath],
    { stdio: 'inherit' },
  );
  if (result.status !== 0) {
    throw new Error(`curl failed while downloading ${outPath}`);
  }
}

function unwrapScreen(payload) {
  if (payload?.screen) return payload.screen;
  if (payload?.screens?.[0]) return payload.screens[0];
  return payload;
}

function summarizeBlocker(error) {
  const message = String(error?.message ?? error);
  if (message.includes('Stitch API has not been used') || message.includes('disabled')) {
    return [
      message,
      '',
      'Set STITCH_QUOTA_PROJECT to a Google Cloud project where stitch.googleapis.com is enabled,',
      'or enable the Stitch API for the current quota project and rerun this script.',
    ].join('\n');
  }
  return message;
}

async function fetchDesignSystem(accessToken, quotaProject, slug, title, assetStubId) {
  const assetId = assetStubId
    .replace(/^asset-stub-assets-/, '')
    .replace(/-\d+$/, '');
  const payload = await callMcpTool(accessToken, quotaProject, 'list_design_systems', {
    projectId,
  });
  const designSystems = payload.designSystems ?? [];
  const designSystem = designSystems.find((item) => item.name?.endsWith(assetId));
  if (!designSystem) {
    throw new Error(`Design system asset was not found: ${assetId}`);
  }

  const metadataPath = path.join(outputDir, `${slug}.metadata.json`);
  const markdownPath = path.join(outputDir, `${slug}.md`);
  writeFileSync(metadataPath, JSON.stringify(designSystem, null, 2));
  writeFileSync(markdownPath, designSystem.designSystem?.styleGuidelines ?? '');

  return {
    title,
    screenId: assetStubId,
    ok: true,
    files: {
      metadata: metadataPath,
      markdown: markdownPath,
    },
  };
}

mkdirSync(outputDir, { recursive: true });

const apiKey = getApiKey();
const accessToken = apiKey ? `api-key:${apiKey}` : await getAccessToken();
const quotaProject = getQuotaProject();
const manifest = {
  projectTitle: 'Glory Grid: Arcade Fintech',
  projectId,
  quotaProject,
  exportedAt: new Date().toISOString(),
  screens: [],
};

for (const [slug, title, screenId] of screens) {
  console.log(`Fetching ${title}...`);
  try {
    if (screenId.startsWith('asset-stub-assets-')) {
      manifest.screens.push(
        await fetchDesignSystem(accessToken, quotaProject, slug, title, screenId),
      );
      continue;
    }

    const payload = await callMcpTool(accessToken, quotaProject, 'get_screen', {
      name: `projects/${projectId}/screens/${screenId}`,
      projectId,
      screenId,
    });
    const screen = unwrapScreen(payload);
    const metadataPath = path.join(outputDir, `${slug}.metadata.json`);
    writeFileSync(metadataPath, JSON.stringify(screen, null, 2));

    const htmlUrl = firstDownloadUrl(screen.htmlCode);
    const screenshotUrl = firstDownloadUrl(screen.screenshot);
    const designSystemUrl = firstDownloadUrl(screen.designSystem);

    const files = { metadata: metadataPath };
    if (htmlUrl) {
      const htmlPath = path.join(outputDir, `${slug}.html`);
      download(htmlUrl, htmlPath);
      files.html = htmlPath;
    }
    if (screenshotUrl) {
      const pngPath = path.join(outputDir, `${slug}.png`);
      download(fullResolutionImageUrl(screenshotUrl), pngPath);
      files.screenshot = pngPath;
    }
    if (designSystemUrl) {
      const designPath = path.join(outputDir, `${slug}.design-system`);
      download(designSystemUrl, designPath);
      files.designSystem = designPath;
    }

    manifest.screens.push({ title, screenId, ok: true, files });
  } catch (error) {
    const message = summarizeBlocker(error);
    console.error(`Could not fetch ${title}: ${message}`);
    manifest.screens.push({ title, screenId, ok: false, error: message });
  }
}

const manifestPath = path.join(outputDir, 'manifest.json');
writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
console.log(`Wrote manifest: ${manifestPath}`);

const failures = manifest.screens.filter((screen) => !screen.ok);
if (failures.length > 0) {
  process.exitCode = 1;
}
