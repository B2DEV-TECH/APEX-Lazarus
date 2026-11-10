// APEX Lazarus: screenshots of the Lazarus Console (application 1430, workspace
// LZ_DEV) for the documentation and for publishing progress.
//
//   node scripts/console-shot.cjs <out-dir> [incident-id ...]
//
// Writes incidents.png (the list) and incident-<id>.png (the detail page,
// opened through the report link so the URL carries a valid checksum).
// Credentials come from the ignored .local/oracle.json and are never printed.
// Playwright and the browser channel are resolved as in browser-probe.cjs.
'use strict';

const fs = require('fs');
const path = require('path');
const { chromium } = require(process.env.LZ_PLAYWRIGHT || 'playwright');

const repo = path.resolve(__dirname, '..');
const config = JSON.parse(
    fs.readFileSync(path.join(repo, '.local', 'oracle.json'), 'utf8').replace(/^﻿/, ''));

const [outDir, ...incidents] = process.argv.slice(2);
if (!outDir) {
    console.error('usage: node scripts/console-shot.cjs <out-dir> [incident-id ...]');
    process.exit(2);
}
const appUrl = `${config.baseUrl}/r/lz_dev/lazarus-console`;

(async () => {
    fs.mkdirSync(outDir, { recursive: true });
    const browser = await chromium.launch({ channel: process.env.LZ_BROWSER_CHANNEL || undefined });
    try {
        const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
        await page.goto(`${appUrl}/incidents`);
        if (await page.locator('#P9999_USERNAME').count() > 0) {
            await page.fill('#P9999_USERNAME', config.apexUser);
            await page.fill('#P9999_PASSWORD', config.apexPasswords.LZ_DEV);
            await page.click('button:has-text("Sign In")');
            await page.waitForURL((url) => !url.pathname.endsWith('/login'), { timeout: 20000 })
                .catch(() => { throw new Error('login failed'); });
        }
        await page.waitForLoadState('networkidle');
        const listFile = path.join(outDir, 'incidents.png');
        await page.screenshot({ path: listFile, fullPage: true });
        console.log(JSON.stringify({ shot: listFile, title: await page.title() }));

        const listUrl = page.url();
        for (const id of incidents) {
            await page.goto(listUrl);
            await page.click(`td[headers="INCIDENT_ID"] a:text-is("${id}")`);
            await page.waitForLoadState('networkidle');
            const file = path.join(outDir, `incident-${id}.png`);
            await page.screenshot({ path: file, fullPage: true });
            const errors = await page.evaluate(() =>
                Array.from(document.querySelectorAll('.t-Alert--danger, .a-Notification--error, .t-Body-content'))
                    .map((node) => (node.innerText.match(/ORA-\d{5}[^\n]*|ERR-\d+[^\n]*/g) || []))
                    .flat().slice(0, 3));
            console.log(JSON.stringify({ shot: file, title: await page.title(), errors }));
        }
    } finally {
        await browser.close();
    }
})().catch((error) => {
    console.error(String(error && error.message || error));
    process.exit(1);
});
