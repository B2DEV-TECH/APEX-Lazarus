// APEX Lazarus: drives the demo application in a real browser so that errors
// go through the APEX engine and its error handling function.
//
//   node scripts/browser-probe.cjs <env> <step> [<step> ...]
//
//   env   prd (application 1410, workspace LZ_PRD) or dev (1420, LZ_DEV)
//   step  employees  open the Employees report (page 2)
//         p01403     page 90, process with no data found
//         p01422     page 90, process with too many rows
//         c06502     page 90, computation with a buffer too small
//         v06502     page 90, validation on a non-numeric amount
//
// Credentials come from the ignored .local/oracle.json and are never printed.
// Playwright is resolved from LZ_PLAYWRIGHT (a module path) or the default
// resolution; LZ_BROWSER_CHANNEL selects an installed browser such as msedge.
'use strict';

const fs = require('fs');
const path = require('path');
const { chromium } = require(process.env.LZ_PLAYWRIGHT || 'playwright');

const repo = path.resolve(__dirname, '..');
const config = JSON.parse(
    fs.readFileSync(path.join(repo, '.local', 'oracle.json'), 'utf8').replace(/^﻿/, ''));

const environments = {
    prd: { workspace: 'LZ_PRD' },
    dev: { workspace: 'LZ_DEV' },
};

const [envName, ...steps] = process.argv.slice(2);
const env = environments[envName];
if (!env || steps.length === 0) {
    console.error('usage: node scripts/browser-probe.cjs <prd|dev> <step> [<step> ...]');
    process.exit(2);
}
const appUrl = `${config.baseUrl}/r/${env.workspace.toLowerCase()}/lazarus-demo`;

// APEX keeps the session in the URL; every navigation after login carries it.
let session = '';
const pageUrl = (alias, request) =>
    `${appUrl}/${alias}?session=${session}` + (request ? `&request=${request}` : '');

// Visible outcome of a page: notification or error text, without the chrome.
async function outcome(page) {
    return page.evaluate(() => {
        const pick = (selector) => Array.from(document.querySelectorAll(selector))
            .map((node) => node.innerText.trim()).filter(Boolean);
        const messages = [
            ...pick('#t_Alert_Notification'),
            ...pick('.a-Notification'),
            ...pick('.t-Alert--danger'),
            ...pick('.t-Body-content .t-Alert'),
        ];
        const body = (document.querySelector('.t-Body-content') || document.body).innerText;
        const oraInBody = (body.match(/ORA-\d{5}[^\n]*/g) || []).slice(0, 3);
        return { title: document.title, messages: [...new Set(messages)].slice(0, 3), oraInBody };
    });
}

async function login(page) {
    await page.goto(`${appUrl}/home`);
    if (await page.locator('#P9999_USERNAME').count() === 0) {
        return;
    }
    await page.fill('#P9999_USERNAME', config.apexUser);
    await page.fill('#P9999_PASSWORD', config.apexPasswords[env.workspace]);
    await page.click('button:has-text("Sign In")');
    await page.waitForURL((url) => !url.pathname.endsWith('/login'), { timeout: 20000 })
        .catch(() => { throw new Error('login failed'); });
    session = new URL(page.url()).searchParams.get('session') || '';
}

const actions = {
    employees: (page) => page.goto(pageUrl('employees')),
    p01403: (page) => page.goto(pageUrl('handler-probe', 'P01403')),
    p01422: (page) => page.goto(pageUrl('handler-probe', 'P01422')),
    c06502: (page) => page.goto(pageUrl('handler-probe', 'C06502')),
    v06502: async (page) => {
        await page.goto(pageUrl('handler-probe'));
        await page.fill('#P90_TEXT', 'abc');
        await Promise.all([
            page.waitForNavigation({ timeout: 20000 }).catch(() => null),
            page.click('button:has-text("Check amount")'),
        ]);
        await page.waitForTimeout(1500);
    },
};

(async () => {
    const browser = await chromium.launch({ channel: process.env.LZ_BROWSER_CHANNEL || undefined });
    try {
        const page = await browser.newPage();
        await login(page);
        for (const step of steps) {
            if (!actions[step]) {
                throw new Error(`unknown step ${step}`);
            }
            await actions[step](page);
            await page.waitForLoadState('load');
            console.log(JSON.stringify({ env: envName, step, at: new Date().toISOString(), ...(await outcome(page)) }));
        }
    } finally {
        await browser.close();
    }
})().catch((error) => {
    console.error(String(error && error.message || error));
    process.exit(1);
});
